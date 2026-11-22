import AppKit
import VerbiCore

@MainActor
extension AssistantShortcutController {
    func handleFlagsChanged(_ event: ShortcutInputEvent) {
        routeAssistantMonitorEvent(event: event, mode: .allSources)
    }

    func handleKeyDown(_ event: ShortcutInputEvent) {
        if handleShortcutLayerKeyDown(event: event) {
            return
        }

        routeAssistantMonitorEvent(event: event, mode: .inHouseDefinitionOnly)
    }

    func handleKeyUp(_ event: ShortcutInputEvent) {
        routeAssistantMonitorEvent(event: event, mode: .inHouseDefinitionOnly)
    }

    func handleFlagsChanged(_ event: NSEvent) {
        let inputEvent = ShortcutInputEvent(systemEvent: event)
        handleFlagsChanged(inputEvent)
    }

    func handleKeyDown(_ event: NSEvent) {
        let inputEvent = ShortcutInputEvent(systemEvent: event)
        handleKeyDown(inputEvent)
    }

    func handleKeyUp(_ event: NSEvent) {
        let inputEvent = ShortcutInputEvent(systemEvent: event)
        handleKeyUp(inputEvent)
    }

    func routeAssistantMonitorEvent(event: ShortcutInputEvent, mode: ShortcutEventRoutingMode) {
        guard settings.isAssistantEnabled else { return }

        let result = shortcutRouter.routeMonitorEvent(
            configuration: assistantRoutingConfiguration(),
            mode: mode,
            wasPressed: shortcutPressed,
            isDefinitionActive: { [weak self] definition in
                guard let self else { return false }
                return presetState.isShortcutActive(definition, inputEvent: event)
            },
            isModifierGestureActive: { [weak self] gesture in
                guard let self else { return false }
                return presetState.isModifierGestureActive(gesture, inputEvent: event)
            },
            isPresetActive: { [weak self] presetKey in
                guard let self else { return false }
                return presetState.isPresetActive(presetKey, inputEvent: event)
            }
        )

        if let nextPressedState = result.nextPressedState {
            shortcutPressed = nextPressedState
        }

        applyAssistantRoutingOutcomes(result.outcomes)
    }

    func handleShortcutLayerKeyDown(event _: ShortcutInputEvent) -> Bool {
        guard isShortcutLayerArmed else { return false }
        return false
    }

    func handleShortcutDown(activationModeOverride: ShortcutActivationMode? = nil) {
        guard settings.isAssistantEnabled else {
            emitShortcutRejected(
                shortcutTarget: "assistant",
                source: "assistant_shortcut_down",
                trigger: activationModeOverride,
                reason: "assistant_disabled"
            )
            return
        }

        if shouldUseAssistantShortcutLayer {
            let activationMode = activationModeOverride ?? settings.assistantShortcutActivationMode
            if activationMode == .doubleTap {
                emitShortcutRejected(
                    shortcutTarget: "assistant",
                    source: "shortcut_layer",
                    trigger: activationMode,
                    reason: "double_tap_requires_key_up"
                )
                return
            }
            emitShortcutDetected(
                shortcutTarget: "assistant",
                source: "shortcut_layer",
                trigger: activationMode
            )
            armShortcutLayer(
                source: "assistant_shortcut",
                trigger: activationMode.rawValue
            )
            return
        }

        let activationMode = activationModeOverride ?? settings.assistantShortcutActivationMode
        let isRecording = assistantService.isRecording
        let actions = shortcutHandler.handleDown(activationMode: activationMode, isRecording: isRecording)
        applyActions(actions)
    }

    func handleShortcutUp(activationModeOverride: ShortcutActivationMode? = nil) {
        guard settings.isAssistantEnabled else { return }

        if shouldUseAssistantShortcutLayer {
            let activationMode = activationModeOverride ?? settings.assistantShortcutActivationMode
            if activationMode == .doubleTap {
                registerLayerLeaderTap()
            }
            return
        }

        let activationMode = activationModeOverride ?? settings.assistantShortcutActivationMode
        let isRecording = assistantService.isRecording
        let actions = shortcutHandler.handleUp(activationMode: activationMode, isRecording: isRecording)
        applyActions(actions)
    }

    private func applyActions(_ actions: [ShortcutExecutionAction]) {
        actions.dispatch { [weak self] action in
            await self?.performAction(action)
        }
    }

    func assistantRoutingConfiguration() -> ShortcutEventRoutingConfiguration {
        ShortcutEventRoutingConfiguration(
            definition: settings.assistantShortcutDefinition,
            modifierGesture: settings.assistantModifierShortcutGesture,
            presetKey: settings.assistantSelectedPresetKey,
            presetRequiresModifierMonitoring: settings.assistantSelectedPresetKey.requiresModifierMonitoring,
            defaultActivationMode: settings.assistantShortcutActivationMode,
            sources: ShortcutEventRoutingSources(
                inHouseDefinition: "in_house_definition",
                modifierGesture: "modifier_gesture",
                preset: "preset"
            )
        )
    }

    func applyAssistantRoutingOutcomes(_ outcomes: [ShortcutEventRoutingOutcome]) {
        for outcome in outcomes {
            switch outcome {
            case let .detected(source, trigger):
                emitShortcutDetected(
                    shortcutTarget: "assistant",
                    source: source,
                    trigger: trigger
                )
            case let .rejected(source, trigger, reason):
                emitShortcutRejected(
                    shortcutTarget: "assistant",
                    source: source,
                    trigger: trigger,
                    reason: reason
                )
            case let .dispatchDown(activationMode):
                Task { @MainActor [weak self] in
                    await self?.handleShortcutDown(activationModeOverride: activationMode)
                }
            case let .dispatchUp(activationMode):
                Task { @MainActor [weak self] in
                    await self?.handleShortcutUp(activationModeOverride: activationMode)
                }
            }
        }
    }

    func performAction(_ action: ShortcutExecutionAction) async {
        guard settings.isAssistantEnabled else {
            emitShortcutRejected(
                shortcutTarget: "assistant",
                source: "assistant_shortcut_action",
                trigger: settings.assistantShortcutActivationMode,
                reason: "assistant_disabled"
            )
            return
        }

        switch action {
        case .start:
            if let blockingMode = await RecordingExclusivityCoordinator.shared.blockingMode(for: .assistant) {
                emitShortcutRejected(
                    shortcutTarget: "assistant",
                    source: "assistant_shortcut_action",
                    trigger: settings.assistantShortcutActivationMode,
                    reason: "blocked_by_active_\(blockingMode.rawValue)_capture"
                )
                return
            }
            await assistantService.startRecording(flow: .assistantMode)
        case .stop:
            await assistantService.stopAndProcess()
        }
    }
}

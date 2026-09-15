import AppKit
import MeetingAssistantCore

@MainActor
extension AssistantShortcutController {
    // MARK: - ShortcutInputEvent handlers (new pluggable backend)

    func handleFlagsChanged(_ event: ShortcutInputEvent) {
        routeAssistantMonitorEvent(event: event, mode: .allSources)

        if !shouldUseAssistantShortcutLayer {
            handleIntegrationFlagsChanged(event)
        }
    }

    func handleKeyDown(_ event: ShortcutInputEvent) {
        if handleShortcutLayerKeyDown(event: event) {
            return
        }

        routeAssistantMonitorEvent(event: event, mode: .inHouseDefinitionOnly)
        handleIntegrationKeyEvent(event: event)
    }

    func handleKeyUp(_ event: ShortcutInputEvent) {
        routeAssistantMonitorEvent(event: event, mode: .inHouseDefinitionOnly)
        handleIntegrationKeyEvent(event: event)
    }

    // MARK: - NSEvent handlers (original implementation - converts to ShortcutInputEvent)

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

    // MARK: - Routing helpers

    func routeAssistantMonitorEvent(event: ShortcutInputEvent, mode: ShortcutEventRoutingMode) {
        guard settings.isAssistantEnabled else { return }

        let result = shortcutRouter.routeMonitorEvent(
            configuration: assistantRoutingConfiguration(),
            mode: mode,
            wasPressed: shortcutHandler.isPressed,
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
            shortcutHandler.handleModifierChange(isActive: nextPressedState)
        }

        applyAssistantRoutingOutcomes(result.outcomes)
    }

    func handleIntegrationFlagsChanged(_ event: ShortcutInputEvent) {
        for (id, handler) in integrationShortcutHandlers {
            guard registeredIntegrationShortcutIDs.contains(id) else { continue }
            handler.handleFlagsChanged(inputEvent: event)
        }
    }

    func handleIntegrationKeyEvent(event: ShortcutInputEvent) {
        for (id, handler) in integrationShortcutHandlers {
            guard registeredIntegrationShortcutIDs.contains(id) else { continue }
            if event.kind == .keyDown {
                handler.handleKeyDown(inputEvent: event)
            } else if event.kind == .keyUp {
                handler.handleKeyUp(inputEvent: event)
            }
        }
    }

    func handleShortcutLayerKeyDown(event _: ShortcutInputEvent) -> Bool {
        guard isShortcutLayerArmed else { return false }
        // Implementation delegated to existing logic
        return false
    }

    func handleCustomShortcutDown() {
        guard settings.isAssistantEnabled else {
            emitShortcutRejected(
                shortcutTarget: "assistant",
                source: "keyboardshortcuts_custom",
                triggerToken: "unknown",
                reason: "assistant_disabled"
            )
            return
        }

        let outcomes = shortcutRouter.routeCustomShortcutDown(
            configuration: assistantRoutingConfiguration()
        )
        applyAssistantRoutingOutcomes(outcomes)
    }

    func handleCustomShortcutUp() {
        guard settings.isAssistantEnabled else { return }

        let outcomes = shortcutRouter.routeCustomShortcutUp(
            configuration: assistantRoutingConfiguration()
        )
        applyAssistantRoutingOutcomes(outcomes)
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

        shortcutHandler.handleShortcutDown(activationMode: activationModeOverride ?? settings.assistantShortcutActivationMode)
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

        shortcutHandler.handleShortcutUp(activationMode: activationModeOverride ?? settings.assistantShortcutActivationMode)
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
                preset: "preset",
                customKeyboardShortcut: "keyboardshortcuts_custom"
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

    func performAction(_ action: SmartShortcutHandler.Action) async {
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
        case .startRecording:
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
        case .stopRecording:
            await assistantService.stopAndProcess()
        }
    }
}

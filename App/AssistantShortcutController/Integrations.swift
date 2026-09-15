import AppKit
import MeetingAssistantCore

@MainActor
extension AssistantShortcutController {
    func handleIntegrationFlagsChanged(_ event: NSEvent) {
        guard settings.isAssistantEnabled, settings.isAssistantIntegrationsEnabled else {
            return
        }

        for integration in settings.assistantIntegrations where integration.isEnabled {
            let state = integrationState(for: integration.id)
            let handler = integrationShortcutHandlers[integration.id] ?? makeIntegrationShortcutHandler(for: integration.id)
            integrationShortcutHandlers[integration.id] = handler
            routeIntegrationMonitorEvent(
                integration,
                event: event,
                mode: .allSources,
                state: state,
                handler: handler
            )
        }
    }

    func handleIntegrationKeyEvent(_ event: NSEvent) {
        guard settings.isAssistantEnabled, settings.isAssistantIntegrationsEnabled else {
            return
        }

        guard !shouldUseAssistantShortcutLayer else {
            return
        }

        for integration in settings.assistantIntegrations where integration.isEnabled {
            let state = integrationState(for: integration.id)
            let handler = integrationShortcutHandlers[integration.id] ?? makeIntegrationShortcutHandler(for: integration.id)
            integrationShortcutHandlers[integration.id] = handler
            routeIntegrationMonitorEvent(
                integration,
                event: event,
                mode: .inHouseDefinitionOnly,
                state: state,
                handler: handler
            )
        }
    }

    func handleIntegrationCustomShortcutDown(integrationID: UUID) {
        guard settings.isAssistantEnabled, settings.isAssistantIntegrationsEnabled else {
            emitShortcutRejected(
                shortcutTarget: "integration",
                source: "integration_keyboardshortcuts_custom",
                triggerToken: "unknown",
                reason: settings.isAssistantEnabled ? "integrations_disabled" : "assistant_disabled"
            )
            return
        }

        guard let integration = integration(for: integrationID) else {
            emitShortcutRejected(
                shortcutTarget: "integration",
                source: "integration_keyboardshortcuts_custom",
                triggerToken: "unknown",
                reason: "integration_missing"
            )
            return
        }

        guard integration.isEnabled else {
            emitShortcutRejected(
                shortcutTarget: "integration",
                source: "integration_keyboardshortcuts_custom",
                trigger: integration.shortcutActivationMode,
                reason: "integration_disabled"
            )
            return
        }

        let outcomes = shortcutRouter.routeCustomShortcutDown(
            configuration: integrationRoutingConfiguration(for: integration)
        )
        applyIntegrationRoutingOutcomes(outcomes, integrationID: integrationID)
    }

    func handleIntegrationCustomShortcutUp(integrationID: UUID) {
        guard settings.isAssistantEnabled, settings.isAssistantIntegrationsEnabled else {
            return
        }

        guard let integration = integration(for: integrationID),
              integration.isEnabled,
              integration.shortcutDefinition == nil,
              integration.modifierShortcutGesture == nil,
              integration.shortcutPresetKey == .custom
        else {
            return
        }

        let outcomes = shortcutRouter.routeCustomShortcutUp(
            configuration: integrationRoutingConfiguration(for: integration)
        )
        applyIntegrationRoutingOutcomes(outcomes, integrationID: integrationID)
    }

    func handleIntegrationShortcutDown(
        integrationID: UUID,
        activationModeOverride: ShortcutActivationMode? = nil
    ) {
        guard settings.isAssistantEnabled, settings.isAssistantIntegrationsEnabled else {
            emitShortcutRejected(
                shortcutTarget: "integration",
                source: "integration_shortcut_down",
                trigger: activationModeOverride,
                reason: settings.isAssistantEnabled ? "integrations_disabled" : "assistant_disabled"
            )
            return
        }

        guard let integration = integration(for: integrationID), integration.isEnabled else {
            emitShortcutRejected(
                shortcutTarget: "integration",
                source: "integration_shortcut_down",
                trigger: activationModeOverride,
                reason: "integration_unavailable"
            )
            return
        }

        settings.assistantSelectedIntegrationId = integrationID
        let shortcutHandler = integrationShortcutHandlers[integrationID] ?? makeIntegrationShortcutHandler(for: integrationID)
        integrationShortcutHandlers[integrationID] = shortcutHandler
        shortcutHandler.handleShortcutDown(activationMode: activationModeOverride ?? integration.shortcutActivationMode)
    }

    func handleIntegrationShortcutUp(
        integrationID: UUID,
        activationModeOverride: ShortcutActivationMode? = nil
    ) {
        guard settings.isAssistantEnabled, settings.isAssistantIntegrationsEnabled else {
            return
        }

        guard let integration = integration(for: integrationID), integration.isEnabled else {
            return
        }

        let shortcutHandler = integrationShortcutHandlers[integrationID] ?? makeIntegrationShortcutHandler(for: integrationID)
        integrationShortcutHandlers[integrationID] = shortcutHandler
        shortcutHandler.handleShortcutUp(activationMode: activationModeOverride ?? integration.shortcutActivationMode)
    }

    func performIntegrationAction(_ action: SmartShortcutHandler.Action, integrationID: UUID) async {
        guard settings.isAssistantEnabled else {
            emitShortcutRejected(
                shortcutTarget: "integration",
                source: "integration_shortcut_action",
                triggerToken: "integration",
                reason: "assistant_disabled"
            )
            return
        }

        switch action {
        case .startRecording:
            if let blockingMode = await RecordingExclusivityCoordinator.shared.blockingMode(for: .assistant) {
                emitShortcutRejected(
                    shortcutTarget: "integration",
                    source: "integration_shortcut_action",
                    triggerToken: "integration",
                    reason: "blocked_by_active_\(blockingMode.rawValue)_capture"
                )
                return
            }
            settings.assistantSelectedIntegrationId = integrationID
            await assistantService.startRecording(flow: .integrationDispatch)
        case .stopRecording:
            await assistantService.stopAndProcess()
        }
    }

    func makeIntegrationShortcutHandler(for integrationID: UUID) -> SmartShortcutHandler {
        SmartShortcutHandler(
            doubleTapInterval: currentDoubleTapInterval,
            isRecordingProvider: { [weak self] in self?.assistantService.isRecording ?? false },
            actionHandler: { [weak self] action in
                Task { @MainActor in
                    await self?.performIntegrationAction(action, integrationID: integrationID)
                }
            }
        )
    }

    func integration(for id: UUID) -> AssistantIntegrationConfig? {
        settings.assistantIntegrations.first(where: { $0.id == id })
    }

    func integrationState(for integrationID: UUID) -> ShortcutActivationState {
        if let existingState = integrationPresetStates[integrationID] {
            return existingState
        }

        let newState = ShortcutActivationState()
        integrationPresetStates[integrationID] = newState
        return newState
    }

    func integrationRoutingConfiguration(
        for integration: AssistantIntegrationConfig
    ) -> ShortcutEventRoutingConfiguration {
        ShortcutEventRoutingConfiguration(
            definition: integration.shortcutDefinition,
            modifierGesture: integration.modifierShortcutGesture,
            presetKey: integration.shortcutPresetKey,
            presetRequiresModifierMonitoring: integration.shortcutPresetKey.requiresModifierMonitoring,
            defaultActivationMode: integration.shortcutActivationMode,
            sources: ShortcutEventRoutingSources(
                inHouseDefinition: "integration_in_house_definition",
                modifierGesture: "integration_modifier_gesture",
                preset: "integration_preset",
                customKeyboardShortcut: "integration_keyboardshortcuts_custom"
            )
        )
    }

    func routeIntegrationMonitorEvent(
        _ integration: AssistantIntegrationConfig,
        event: NSEvent,
        mode: ShortcutEventRoutingMode,
        state: ShortcutActivationState,
        handler: SmartShortcutHandler
    ) {
        let result = shortcutRouter.routeMonitorEvent(
            configuration: integrationRoutingConfiguration(for: integration),
            mode: mode,
            wasPressed: handler.isPressed,
            isDefinitionActive: { definition in
                state.isShortcutActive(definition, event: event)
            },
            isModifierGestureActive: { gesture in
                state.isModifierGestureActive(gesture, event: event)
            },
            isPresetActive: { presetKey in
                state.isPresetActive(presetKey, event: event)
            }
        )

        if let nextPressedState = result.nextPressedState {
            handler.handleModifierChange(isActive: nextPressedState)
        }

        applyIntegrationRoutingOutcomes(result.outcomes, integrationID: integration.id)
    }

    func applyIntegrationRoutingOutcomes(
        _ outcomes: [ShortcutEventRoutingOutcome],
        integrationID: UUID
    ) {
        for outcome in outcomes {
            switch outcome {
            case let .detected(source, trigger):
                emitShortcutDetected(
                    shortcutTarget: "integration",
                    source: source,
                    trigger: trigger
                )
            case let .rejected(source, trigger, reason):
                emitShortcutRejected(
                    shortcutTarget: "integration",
                    source: source,
                    trigger: trigger,
                    reason: reason
                )
            case let .dispatchDown(activationMode):
                Task { @MainActor [weak self] in
                    await self?.handleIntegrationShortcutDown(
                        integrationID: integrationID,
                        activationModeOverride: activationMode
                    )
                }
            case let .dispatchUp(activationMode):
                Task { @MainActor [weak self] in
                    await self?.handleIntegrationShortcutUp(
                        integrationID: integrationID,
                        activationModeOverride: activationMode
                    )
                }
            }
        }
    }
}

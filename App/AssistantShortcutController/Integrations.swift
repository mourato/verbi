import Foundation
import VerbiCore

@MainActor
extension AssistantShortcutController {
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
        let shortcutHandler = integrationShortcutHandlers[integrationID] ?? makeIntegrationShortcutHandler()
        integrationShortcutHandlers[integrationID] = shortcutHandler
        let mode = activationModeOverride ?? integration.shortcutActivationMode
        let isRecording = assistantService.isRecording
        let actions = shortcutHandler.handleDown(activationMode: mode, isRecording: isRecording)
        applyIntegrationActions(actions, integrationID: integrationID)
    }

    func handleIntegrationShortcutUp(
        integrationID: UUID,
        activationModeOverride: ShortcutActivationMode? = nil
    ) {
        guard settings.isAssistantEnabled, settings.isAssistantIntegrationsEnabled, let integration = integration(for: integrationID), integration.isEnabled else {
            return
        }

        let shortcutHandler = integrationShortcutHandlers[integrationID] ?? makeIntegrationShortcutHandler()
        integrationShortcutHandlers[integrationID] = shortcutHandler
        let mode = activationModeOverride ?? integration.shortcutActivationMode
        let isRecording = assistantService.isRecording
        let actions = shortcutHandler.handleUp(activationMode: mode, isRecording: isRecording)
        applyIntegrationActions(actions, integrationID: integrationID)
    }

    func performIntegrationAction(_ action: ShortcutExecutionAction, integrationID: UUID) async {
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
        case .start:
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
        case .stop:
            await assistantService.stopAndProcess()
        }
    }

    func makeIntegrationShortcutHandler() -> ShortcutExecutionEngine {
        ShortcutExecutionEngine(
            doubleTapInterval: currentDoubleTapInterval
        )
    }

    private func applyIntegrationActions(_ actions: [ShortcutExecutionAction], integrationID: UUID) {
        actions.dispatch { [weak self] action in
            await self?.performIntegrationAction(action, integrationID: integrationID)
        }
    }

    func integration(for id: UUID) -> AssistantIntegrationConfig? {
        settings.assistantIntegrations.first(where: { $0.id == id })
    }
}

import AppKit
import MeetingAssistantCore

@MainActor
extension AssistantShortcutController {
    var shouldUseAssistantShortcutLayer: Bool {
        // Layer mode removed from global shortcut runtime.
        false
    }

    var shouldSuppressEnterStopWhileRecording: Bool {
        AssistantShortcutSuppressionPolicy.shouldSuppressEnterStopWhileRecording(
            assistantUseEnterToStopRecording: settings.assistantUseEnterToStopRecording,
            isAssistantRecording: assistantService.isRecording
        )
    }

    var shouldSuppressKeyDownEvents: Bool {
        false
    }

    func refreshShortcutLayerKeySuppression() {
        shortcutLayerKeySuppressor.stop()
    }

    func armShortcutLayer(source: String = "unknown", trigger: String = "unknown") {
        _ = source
        _ = trigger
        refreshShortcutLayerKeySuppression()
        shortcutLayerFeedbackController.hide()
    }

    func disarmShortcutLayer(
        showFeedback: Bool,
        event: AssistantShortcutLayerStateMachine.Event = .disarmedExplicitly,
        transitionSource: String = "unknown"
    ) {
        _ = event
        _ = transitionSource

        shortcutLayerTask?.cancel()
        shortcutLayerTask = nil
        shortcutLayerStateMachine = AssistantShortcutLayerStateMachine()
        refreshShortcutLayerKeySuppression()

        if showFeedback {
            shortcutLayerFeedbackController.showCancelled()
        } else {
            shortcutLayerFeedbackController.hide()
        }
    }

    func registerLayerLeaderTap() {
        // No-op while layer mode is disabled.
    }

    func handleShortcutLayerKeyDown(_ event: NSEvent) -> Bool {
        _ = event
        return false
    }
}

import Foundation
import MeetingAssistantCore

@MainActor
extension AssistantShortcutController {
    func resetShortcutState() {
        lastLayerLeaderTapTime = nil
        disarmShortcutLayer(showFeedback: false)
        presetState.reset()
        shortcutHandler.reset()
        integrationPresetStates.values.forEach { $0.reset() }
        integrationShortcutHandlers.values.forEach { $0.reset() }
    }

    var currentDoubleTapInterval: TimeInterval {
        settings.shortcutDoubleTapIntervalMilliseconds / 1000
    }

    func applyGlobalDoubleTapInterval() {
        let interval = currentDoubleTapInterval
        shortcutHandler.setDoubleTapInterval(interval)
        integrationShortcutHandlers.values.forEach { $0.setDoubleTapInterval(interval) }
    }
}

import Foundation
import VerbiCore

@MainActor
extension AssistantShortcutController {
    func resetShortcutState() {
        lastLayerLeaderTapTime = nil
        disarmShortcutLayer(showFeedback: false)
        presetState.reset()
        shortcutHandler.reset()
        shortcutPressed = false
        integrationShortcutHandlers.values.forEach { $0.reset() }
    }

    var currentDoubleTapInterval: TimeInterval {
        settings.shortcutDoubleTapIntervalMilliseconds / 1000
    }

    func applyGlobalDoubleTapInterval() {
        let interval = currentDoubleTapInterval
        shortcutHandler.updateDoubleTapInterval(interval)
        integrationShortcutHandlers.values.forEach { $0.updateDoubleTapInterval(interval) }
    }
}

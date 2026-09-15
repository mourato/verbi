import AppKit
import MeetingAssistantCore

extension AppDelegate {
    func application(_: NSApplication, open urls: [URL]) {
        for url in urls {
            handleDeepLink(url)
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard let deepLink = AppDeepLink(url: url) else {
            AppLogger.warning(
                "Ignored unsupported deep link",
                category: .general,
                extra: ["scheme": url.scheme ?? "nil", "host": url.host ?? "nil"]
            )
            return
        }

        AppLogger.info(
            "Handling deep link",
            category: .general,
            extra: ["action": deepLink.rawValue]
        )

        switch deepLink {
        case .dictation:
            AppCommandRouter.shared.toggleDictation()
        case .meeting:
            AppCommandRouter.shared.toggleMeeting()
        case .assistant:
            AppCommandRouter.shared.toggleAssistant()
        case .history:
            AppCommandRouter.shared.openHistory()
        case .settings:
            AppCommandRouter.shared.openSettings()
        }
    }
}

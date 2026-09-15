import Foundation
import MeetingAssistantCoreCommon
import SwiftUI

enum WebTargetBrowserNamesFormatter {
    static func formattedNames(
        bundleIdentifiers: [String],
        fallbackBundleIdentifiers: [String],
        localizedListKey: String
    ) -> String {
        let effectiveBundleIdentifiers = bundleIdentifiers.isEmpty ? fallbackBundleIdentifiers : bundleIdentifiers

        if effectiveBundleIdentifiers.isEmpty {
            return "settings.web_targets.browsers.empty".localized
        }

        let names = effectiveBundleIdentifiers
            .map { WebTargetEditorSupport.browserDisplayName(for: $0) }
            .sorted()

        let namesList = names.joined(separator: ", ")
        let localizedTemplate = localizedListKey.localized
        guard localizedTemplate != localizedListKey else {
            return namesList
        }
        return String(format: localizedTemplate, locale: .current, namesList)
    }
}

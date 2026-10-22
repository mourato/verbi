@testable import VerbiCore
import XCTest

@MainActor
final class AppSettingsWebTargetBrowserSyncTests: XCTestCase {
    private var settings: AppSettingsStore!

    override func setUp() async throws {
        settings = .shared
        settings.resetToDefaults()
    }

    override func tearDown() async throws {
        settings.resetToDefaults()
        settings = nil
    }

    func testDictationRules_IncludeCustomChromiumBrowserInEffectiveBrowserList() {
        settings.dictationAppRules = baseBrowserRules + [
            DictationApplicationRule(bundleIdentifier: "com.example.SuperChromium", forceMarkdownOutput: false, outputLanguage: .original),
        ]

        let effective = normalized(settings.effectiveWebTargetBrowserBundleIdentifiers)
        XCTAssertTrue(effective.contains("com.example.superchromium"))
    }

    func testDictationRules_DoNotTreatRegularAppsAsBrowsers() {
        settings.dictationAppRules = baseBrowserRules + [
            DictationApplicationRule(bundleIdentifier: "com.microsoft.VSCode", forceMarkdownOutput: true, outputLanguage: .original),
        ]

        let effective = normalized(settings.effectiveWebTargetBrowserBundleIdentifiers)
        XCTAssertFalse(effective.contains("com.microsoft.vscode"))
    }

    func testDictationRules_AllowFirefoxBundleForWindowTitleFallbackMatching() {
        settings.dictationAppRules = baseBrowserRules + [
            DictationApplicationRule(bundleIdentifier: "org.mozilla.firefox", forceMarkdownOutput: false, outputLanguage: .original),
        ]

        let effective = normalized(settings.effectiveWebTargetBrowserBundleIdentifiers)
        XCTAssertTrue(effective.contains("org.mozilla.firefox"))
    }

    private var baseBrowserRules: [DictationApplicationRule] {
        AppSettingsStore.defaultWebTargetBrowserBundleIdentifiers.map {
            DictationApplicationRule(bundleIdentifier: $0, forceMarkdownOutput: false, outputLanguage: .original)
        }
    }

    private func normalized(_ values: [String]) -> Set<String> {
        Set(values.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
    }
}

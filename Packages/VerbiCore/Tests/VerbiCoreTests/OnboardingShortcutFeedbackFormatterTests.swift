@testable import VerbiCore
@testable import VerbiCoreUI
import XCTest

@MainActor
final class OnboardingShortcutFeedbackFormatterTests: XCTestCase {
    private var settings: AppSettingsStore!

    override func setUp() async throws {
        settings = .shared
        settings.resetToDefaults()
    }

    override func tearDown() async throws {
        settings.resetToDefaults()
        settings = nil
    }

    func testSummaryReturnsNotConfiguredForNilShortcut() {
        let summary = OnboardingShortcutFeedbackFormatter.summary(for: nil)
        XCTAssertEqual(summary, "onboarding.shortcuts.not_configured".localized)
    }

    func testSummaryFormatsModifierAndPrimaryKey() {
        let definition = ShortcutDefinition(
            modifiers: [.option, .command],
            primaryKey: .letter("D", keyCode: 0x02),
            trigger: .singleTap,
        )

        let summary = OnboardingShortcutFeedbackFormatter.summary(for: definition)
        XCTAssertEqual(summary, "⌘ ⌥ D")
    }

    func testSummaryFormatsDoubleTapModifierAsRepeatedToken() {
        let definition = ShortcutDefinition(
            modifiers: [.rightShift],
            primaryKey: nil,
            trigger: .doubleTap,
        )

        let summary = OnboardingShortcutFeedbackFormatter.summary(for: definition)
        XCTAssertEqual(summary, "⇧ ⇧")
    }

    func testCurrentDefinitionUsesAssistantShortcutForAssistantType() async {
        let shortcutViewModel = ShortcutSettingsViewModel()
        let assistantViewModel = AssistantShortcutSettingsViewModel()
        let assistantShortcut = ShortcutDefinition(
            modifiers: [.control],
            primaryKey: .letter("A", keyCode: 0x00),
            trigger: .singleTap,
        )

        assistantViewModel.assistantShortcutDefinition = assistantShortcut
        await Task.yield()

        let current = OnboardingShortcutFeedbackFormatter.currentDefinition(
            for: .assistant,
            shortcutViewModel: shortcutViewModel,
            assistantViewModel: assistantViewModel,
        )

        XCTAssertEqual(current, assistantShortcut)
    }

    func testIsUsingDefaultRecognizesAssistantDefaultDefinition() {
        let isDefault = OnboardingShortcutFeedbackFormatter.isUsingDefault(
            current: AppSettingsStore.defaultAssistantShortcutDefinition,
            type: .assistant,
        )
        XCTAssertTrue(isDefault)
    }
}

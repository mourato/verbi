@testable import VerbiCore
import XCTest

@MainActor
final class ShortcutSettingsViewModelTests: XCTestCase {
    private var settings: AppSettingsStore!

    override func setUp() async throws {
        settings = .shared
        settings.resetToDefaults()
        ShortcutCaptureHealthStore.reset()
    }

    override func tearDown() async throws {
        ShortcutCaptureHealthStore.reset()
        settings.resetToDefaults()
        settings = nil
    }

    func testClearingDictationShortcutSetsPresetToNotSpecified() async {
        let viewModel = ShortcutSettingsViewModel()
        let shortcut = ShortcutDefinition(
            modifiers: [.command],
            primaryKey: .letter("K", keyCode: 0x28),
            trigger: .singleTap,
        )

        viewModel.dictationShortcutDefinition = shortcut
        await Task.yield()
        XCTAssertEqual(settings.dictationSelectedPresetKey, .custom)

        viewModel.dictationShortcutDefinition = nil
        await Task.yield()

        XCTAssertNil(settings.dictationShortcutDefinition)
        XCTAssertNil(settings.dictationModifierShortcutGesture)
        XCTAssertEqual(settings.dictationSelectedPresetKey, .notSpecified)
        XCTAssertEqual(viewModel.dictationSelectedPresetKey, .notSpecified)
    }

    func testClearingMeetingShortcutSetsPresetToNotSpecified() async {
        let viewModel = ShortcutSettingsViewModel()
        let shortcut = ShortcutDefinition(
            modifiers: [.control],
            primaryKey: .letter("J", keyCode: 0x26),
            trigger: .singleTap,
        )

        viewModel.meetingShortcutDefinition = shortcut
        await Task.yield()
        XCTAssertEqual(settings.meetingSelectedPresetKey, .custom)

        viewModel.meetingShortcutDefinition = nil
        await Task.yield()

        XCTAssertNil(settings.meetingShortcutDefinition)
        XCTAssertNil(settings.meetingModifierShortcutGesture)
        XCTAssertEqual(settings.meetingSelectedPresetKey, .notSpecified)
        XCTAssertEqual(viewModel.meetingSelectedPresetKey, .notSpecified)
    }

    func testShortcutCaptureHealthPresentationUpdatesWhenGlobalHealthBecomesDegraded() async {
        let viewModel = ShortcutSettingsViewModel()
        XCTAssertNil(viewModel.shortcutCaptureHealthPresentation)

        ShortcutCaptureHealthStore.updateHealth(
            scope: .global,
            result: "degraded",
            reasonToken: "accessibility_denied",
            requiresGlobalCapture: true,
            accessibilityTrusted: false,
            eventTapExpected: false,
            eventTapActive: false,
        )
        await Task.yield()

        XCTAssertEqual(
            viewModel.shortcutCaptureHealthPresentation?.messageKey,
            "settings.shortcuts.health.degraded.message.permissions_accessibility",
        )
        XCTAssertEqual(viewModel.shortcutCaptureHealthPresentation?.isFallback, false)
    }

    func testDictationShortcutRejectsEnterKey() async {
        let viewModel = ShortcutSettingsViewModel()
        let enterShortcut = ShortcutDefinition(
            modifiers: [.command],
            primaryKey: .symbol("↩", keyCode: 0x24),
            trigger: .singleTap,
        )

        viewModel.dictationShortcutDefinition = enterShortcut
        await Task.yield()

        XCTAssertEqual(settings.dictationShortcutDefinition, AppSettingsStore.defaultDictationShortcutDefinition)
        XCTAssertEqual(
            viewModel.dictationModifierConflictMessage,
            "settings.shortcuts.modifier.primary_key_required".localized,
        )
    }
}

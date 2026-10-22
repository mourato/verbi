@testable import VerbiCore
import XCTest

@MainActor
final class AssistantShortcutSettingsViewModelTests: XCTestCase {
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

    func testClearingAssistantShortcutSetsPresetToNotSpecified() async {
        let viewModel = AssistantShortcutSettingsViewModel()
        let shortcut = ShortcutDefinition(
            modifiers: [.command],
            primaryKey: .letter("A", keyCode: 0x00),
            trigger: .singleTap,
        )

        viewModel.assistantShortcutDefinition = shortcut
        await Task.yield()
        XCTAssertEqual(settings.assistantSelectedPresetKey, .custom)

        viewModel.assistantShortcutDefinition = nil
        await Task.yield()

        XCTAssertNil(settings.assistantShortcutDefinition)
        XCTAssertNil(settings.assistantModifierShortcutGesture)
        XCTAssertEqual(settings.assistantSelectedPresetKey, .notSpecified)
        XCTAssertEqual(viewModel.selectedPresetKey, .notSpecified)
    }

    func testAssistantShortcutRejectsEnterKey() async {
        let viewModel = AssistantShortcutSettingsViewModel()
        let enterShortcut = ShortcutDefinition(
            modifiers: [.command],
            primaryKey: .symbol("↩", keyCode: 0x24),
            trigger: .singleTap,
        )

        viewModel.assistantShortcutDefinition = enterShortcut
        await Task.yield()

        XCTAssertEqual(settings.assistantShortcutDefinition, AppSettingsStore.defaultAssistantShortcutDefinition)
        XCTAssertEqual(
            viewModel.assistantModifierConflictMessage,
            "settings.shortcuts.modifier.primary_key_required".localized,
        )
    }

    func testShortcutCaptureHealthPresentationUpdatesWhenAssistantFallbackIsActive() async {
        let viewModel = AssistantShortcutSettingsViewModel()
        XCTAssertNil(viewModel.shortcutCaptureHealthPresentation)

        ShortcutCaptureHealthStore.updateHealth(
            scope: .assistant,
            result: "degraded",
            reasonToken: "event_tap_inactive",
            requiresGlobalCapture: true,
            accessibilityTrusted: true,
            eventTapExpected: true,
            eventTapActive: false,
        )
        await Task.yield()

        XCTAssertEqual(viewModel.shortcutCaptureHealthPresentation?.badgeKey, "settings.shortcuts.health.badge.fallback")
        XCTAssertEqual(viewModel.shortcutCaptureHealthPresentation?.isFallback, true)
    }

    func testAssistantShortcutConflictWithIntegrationShowsModifierConflictMessage() async {
        let integration = AssistantIntegrationConfig(
            name: "Raycast",
            kind: .deeplink,
            isEnabled: true,
            deepLink: AssistantIntegrationConfig.defaultRaycastDeepLink,
            shortcutDefinition: ShortcutDefinition(
                modifiers: [.command],
                primaryKey: .letter("R", keyCode: 0x0f),
                trigger: .singleTap,
            ),
            shortcutPresetKey: .custom,
            shortcutActivationMode: .toggle,
        )
        settings.assistantIntegrations = [integration]

        let viewModel = AssistantShortcutSettingsViewModel()

        viewModel.assistantShortcutDefinition = ShortcutDefinition(
            modifiers: [.command],
            primaryKey: .letter("R", keyCode: 0x0f),
            trigger: .singleTap,
        )
        await Task.yield()

        XCTAssertEqual(settings.assistantShortcutDefinition, AppSettingsStore.defaultAssistantShortcutDefinition)
        XCTAssertEqual(
            viewModel.assistantModifierConflictMessage,
            "settings.shortcuts.modifier.conflict".localized(with: integration.name),
        )
    }
}

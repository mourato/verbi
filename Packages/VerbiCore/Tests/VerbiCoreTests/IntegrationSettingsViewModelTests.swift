@testable import VerbiCore
import XCTest

@MainActor
final class IntegrationSettingsViewModelTests: XCTestCase {
    private var settings: AppSettingsStore!

    override func setUp() async throws {
        settings = .shared
        settings.resetToDefaults()
    }

    override func tearDown() async throws {
        settings.resetToDefaults()
        settings = nil
    }

    func testClearingIntegrationShortcutSetsPresetToNotSpecified() {
        let viewModel = IntegrationSettingsViewModel()
        viewModel.addIntegration()

        guard let integrationID = viewModel.customIntegrations.last?.id else {
            XCTFail("Expected a custom integration after addIntegration")
            return
        }

        let shortcut = ShortcutDefinition(
            modifiers: [.option, .command],
            primaryKey: .letter("T", keyCode: 0x11),
            trigger: .singleTap,
        )

        XCTAssertNil(viewModel.setIntegrationShortcutDefinition(shortcut, for: integrationID))
        XCTAssertEqual(viewModel.integration(for: integrationID)?.shortcutPresetKey, .custom)

        XCTAssertNil(viewModel.setIntegrationShortcutDefinition(nil, for: integrationID))
        XCTAssertNil(viewModel.integration(for: integrationID)?.shortcutDefinition)
        XCTAssertNil(viewModel.integration(for: integrationID)?.modifierShortcutGesture)
        XCTAssertEqual(viewModel.integration(for: integrationID)?.shortcutPresetKey, .notSpecified)
    }

    func testAddIntegrationDefaultsOverlayVisibilityFlagsToFalse() {
        let viewModel = IntegrationSettingsViewModel()

        viewModel.addIntegration()

        let integration = viewModel.customIntegrations.last
        XCTAssertEqual(integration?.showsPromptSelectorInOverlay, false)
        XCTAssertEqual(integration?.showsLanguageSelectorInOverlay, false)
    }

    func testIntegrationShortcutConflictWithAssistantReturnsModifierConflictMessage() {
        settings.assistantShortcutDefinition = ShortcutDefinition(
            modifiers: [.command],
            primaryKey: .letter("K", keyCode: 0x28),
            trigger: .singleTap,
        )

        let viewModel = IntegrationSettingsViewModel()
        viewModel.addIntegration()

        guard let integrationID = viewModel.customIntegrations.last?.id else {
            XCTFail("Expected a custom integration after addIntegration")
            return
        }

        viewModel.setIntegrationEnabled(true, for: integrationID)

        let message = viewModel.setIntegrationShortcutDefinition(
            ShortcutDefinition(
                modifiers: [.leftCommand],
                primaryKey: .letter("K", keyCode: 0x28),
                trigger: .singleTap,
            ),
            for: integrationID,
        )

        XCTAssertEqual(
            message,
            "settings.shortcuts.modifier.conflict".localized(with: "settings.assistant.toggle_command".localized),
        )
        XCTAssertNil(viewModel.integration(for: integrationID)?.shortcutDefinition)
    }

    func testIntegrationShortcutDefinitionWithoutPrimaryKeyReturnsValidationMessage() {
        let viewModel = IntegrationSettingsViewModel()
        viewModel.addIntegration()

        guard let integrationID = viewModel.customIntegrations.last?.id else {
            XCTFail("Expected a custom integration after addIntegration")
            return
        }

        viewModel.setIntegrationEnabled(true, for: integrationID)

        let message = viewModel.setIntegrationShortcutDefinition(
            ShortcutDefinition(
                modifiers: [.rightControl],
                primaryKey: nil,
                trigger: .doubleTap,
            ),
            for: integrationID,
        )

        XCTAssertEqual(message, "settings.shortcuts.modifier.primary_key_required".localized)
        XCTAssertNil(viewModel.integration(for: integrationID)?.shortcutDefinition)
    }

    func testIntegrationModifierlessFunctionShortcutIsAccepted() {
        let viewModel = IntegrationSettingsViewModel()
        viewModel.addIntegration()

        guard let integrationID = viewModel.customIntegrations.last?.id else {
            XCTFail("Expected a custom integration after addIntegration")
            return
        }

        viewModel.setIntegrationEnabled(true, for: integrationID)

        let shortcut = ShortcutDefinition(
            modifiers: [],
            primaryKey: .function(index: 5, keyCode: 0x60),
            trigger: .singleTap,
        )

        let message = viewModel.setIntegrationShortcutDefinition(shortcut, for: integrationID)

        XCTAssertNil(message)
        XCTAssertEqual(viewModel.integration(for: integrationID)?.shortcutDefinition, shortcut)
        XCTAssertEqual(viewModel.integration(for: integrationID)?.shortcutPresetKey, .custom)
    }

    func testIntegrationShortcutRejectsEnterKey() {
        let viewModel = IntegrationSettingsViewModel()
        viewModel.addIntegration()

        guard let integrationID = viewModel.customIntegrations.last?.id else {
            XCTFail("Expected a custom integration after addIntegration")
            return
        }

        viewModel.setIntegrationEnabled(true, for: integrationID)

        let message = viewModel.setIntegrationShortcutDefinition(
            ShortcutDefinition(
                modifiers: [.command],
                primaryKey: .symbol("↩", keyCode: 0x24),
                trigger: .singleTap,
            ),
            for: integrationID,
        )

        XCTAssertEqual(message, "settings.shortcuts.modifier.primary_key_required".localized)
        XCTAssertNil(viewModel.integration(for: integrationID)?.shortcutDefinition)
    }

    func testSaveIntegrationPersistsOverlayVisibilityFlags() {
        let viewModel = IntegrationSettingsViewModel()
        viewModel.addIntegration()

        guard var integration = viewModel.customIntegrations.last else {
            XCTFail("Expected a custom integration after addIntegration")
            return
        }

        integration.showsPromptSelectorInOverlay = true
        integration.showsLanguageSelectorInOverlay = true
        viewModel.saveIntegration(integration)

        XCTAssertEqual(viewModel.integration(for: integration.id)?.showsPromptSelectorInOverlay, true)
        XCTAssertEqual(viewModel.integration(for: integration.id)?.showsLanguageSelectorInOverlay, true)
        XCTAssertEqual(settings.assistantIntegrations.last?.showsPromptSelectorInOverlay, true)
        XCTAssertEqual(settings.assistantIntegrations.last?.showsLanguageSelectorInOverlay, true)
    }

    func testSaveBuiltInIntegrationPersistsOverlayVisibilityFlags() {
        let viewModel = IntegrationSettingsViewModel()

        guard var integration = viewModel.builtInIntegrations.first else {
            XCTFail("Expected built-in integration")
            return
        }

        integration.showsPromptSelectorInOverlay = true
        integration.showsLanguageSelectorInOverlay = false
        viewModel.saveIntegration(integration)

        XCTAssertEqual(viewModel.builtInIntegrations.first?.showsPromptSelectorInOverlay, true)
        XCTAssertEqual(settings.assistantIntegrations.first?.showsPromptSelectorInOverlay, true)
        XCTAssertEqual(settings.assistantIntegrations.first?.showsLanguageSelectorInOverlay, false)
    }
}

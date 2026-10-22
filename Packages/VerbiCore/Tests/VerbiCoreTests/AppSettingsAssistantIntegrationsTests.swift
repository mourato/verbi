@testable import VerbiCore
import XCTest

@MainActor
final class AppSettingsAssistantIntegrationsTests: XCTestCase {
    private var settings: AppSettingsStore!

    override func setUp() async throws {
        settings = .shared
        settings.resetToDefaults()
    }

    override func tearDown() async throws {
        settings.resetToDefaults()
        settings = nil
    }

    func testDefaults_SeedsRaycastIntegrationAsSelected() {
        XCTAssertEqual(settings.assistantIntegrations.count, 1)

        let raycast = settings.assistantIntegrations.first
        XCTAssertEqual(raycast?.name, "Raycast")
        XCTAssertEqual(raycast?.deepLink, AssistantIntegrationConfig.defaultRaycastDeepLink)
        XCTAssertEqual(raycast?.showsPromptSelectorInOverlay, false)
        XCTAssertEqual(raycast?.showsLanguageSelectorInOverlay, false)
        XCTAssertEqual(settings.assistantSelectedIntegrationId, raycast?.id)
        XCTAssertEqual(settings.assistantSelectedIntegration?.id, raycast?.id)
        XCTAssertEqual(raycast?.shortcutDefinition, AssistantIntegrationConfig.defaultRaycast.shortcutDefinition)
    }

    func testUpsertAssistantIntegration_UpdatesExistingIntegration() {
        guard var integration = settings.assistantSelectedIntegration else {
            XCTFail("Expected default selected integration")
            return
        }

        integration.isEnabled = true
        integration.deepLink = "raycast://ai-commands/custom-command"

        settings.upsertAssistantIntegration(integration)

        XCTAssertEqual(settings.assistantIntegrations.count, 1)
        XCTAssertEqual(settings.assistantSelectedIntegration?.isEnabled, true)
        XCTAssertEqual(settings.assistantSelectedIntegration?.deepLink, AssistantIntegrationConfig.defaultRaycastDeepLink)
    }

    func testUpsertAssistantIntegration_AppendsNewIntegration() {
        let custom = AssistantIntegrationConfig(
            name: "Custom Integration",
            kind: .deeplink,
            isEnabled: false,
            deepLink: "raycast://ai-commands/custom",
        )

        settings.upsertAssistantIntegration(custom)

        XCTAssertEqual(settings.assistantIntegrations.count, 2)
        XCTAssertTrue(settings.assistantIntegrations.contains(where: { $0.id == custom.id }))
    }

    func testRemoveAssistantIntegration_ReassignsSelectionWhenRemovingCurrent() {
        let custom = AssistantIntegrationConfig(
            name: "Custom Integration",
            kind: .deeplink,
            isEnabled: true,
            deepLink: "raycast://ai-commands/custom",
        )
        settings.upsertAssistantIntegration(custom)
        settings.assistantSelectedIntegrationId = custom.id

        settings.removeAssistantIntegration(id: custom.id)

        XCTAssertEqual(settings.assistantIntegrations.count, 1)
        XCTAssertEqual(settings.assistantSelectedIntegrationId, AssistantIntegrationConfig.raycastDefaultID)
    }

    func testIntegrationsEmpty_FallsBackToDefaultRaycast() {
        settings.assistantIntegrations = []

        XCTAssertEqual(settings.assistantIntegrations.count, 1)
        XCTAssertEqual(settings.assistantIntegrations.first?.id, AssistantIntegrationConfig.raycastDefaultID)
        XCTAssertEqual(settings.assistantSelectedIntegrationId, AssistantIntegrationConfig.raycastDefaultID)
    }

    func testAssistantIntegrationConfigCodableRoundTripPreservesShortcutDefinition() throws {
        let original = AssistantIntegrationConfig(
            name: "Test Integration",
            kind: .deeplink,
            isEnabled: true,
            deepLink: "raycast://test",
            shortcutDefinition: ShortcutDefinition(
                modifiers: [.command, .option],
                primaryKey: .letter("T", keyCode: 0x11),
                trigger: .singleTap,
            ),
            shortcutPresetKey: .custom,
            shortcutActivationMode: .toggle,
            showsPromptSelectorInOverlay: true,
            showsLanguageSelectorInOverlay: true,
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AssistantIntegrationConfig.self, from: data)

        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.shortcutDefinition, original.shortcutDefinition)
        XCTAssertEqual(decoded.showsPromptSelectorInOverlay, true)
        XCTAssertEqual(decoded.showsLanguageSelectorInOverlay, true)
    }

    func testAssistantIntegrationConfigDecodesLegacyLayerKeysWithoutPersistingThem() throws {
        let payload = Data("""
        {
          "id": "00000000-0000-0000-0000-000000000111",
          "name": "Legacy",
          "kind": "deeplink",
          "isEnabled": true,
          "deepLink": "raycast://legacy",
          "layerShortcutKey": "R",
          "leaderModeEnabled": true
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(AssistantIntegrationConfig.self, from: payload)

        XCTAssertEqual(decoded.name, "Legacy")
        XCTAssertEqual(decoded.deepLink, "raycast://legacy")
        XCTAssertNil(decoded.shortcutDefinition)
        XCTAssertEqual(decoded.showsPromptSelectorInOverlay, false)
        XCTAssertEqual(decoded.showsLanguageSelectorInOverlay, false)
    }
}

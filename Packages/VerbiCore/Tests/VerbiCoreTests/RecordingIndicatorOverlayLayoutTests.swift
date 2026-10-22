@testable import VerbiCore
import XCTest

@MainActor
final class RecordingIndicatorOverlayLayoutTests: XCTestCase {
    private var settings: AppSettingsStore!

    override func setUp() async throws {
        settings = .shared
        settings.resetToDefaults()
    }

    override func tearDown() async throws {
        settings.resetToDefaults()
        settings = nil
    }

    func testDictationLayoutShowsPromptAndLanguage() {
        let layout = RecordingIndicatorOverlayLayout.resolve(
            renderState: RecordingIndicatorRenderState(mode: .recording, kind: .dictation),
            settingsStore: settings,
        )

        XCTAssertEqual(layout.showsPromptSelector, true)
        XCTAssertEqual(layout.showsLanguageSelector, true)
        XCTAssertEqual(layout.showsMeetingTimer, false)
        XCTAssertEqual(layout.auxiliaryControlCount, 2)
    }

    func testAssistantLayoutShowsOnlyMainPill() {
        let layout = RecordingIndicatorOverlayLayout.resolve(
            renderState: RecordingIndicatorRenderState(mode: .recording, kind: .assistant),
            settingsStore: settings,
        )

        XCTAssertEqual(layout.showsPromptSelector, false)
        XCTAssertEqual(layout.showsLanguageSelector, false)
        XCTAssertEqual(layout.showsMeetingTimer, false)
        XCTAssertEqual(layout.auxiliaryControlCount, 0)
    }

    func testAssistantIntegrationLayoutRespectsIntegrationVisibilityFlags() {
        let integration = AssistantIntegrationConfig(
            id: UUID(),
            name: "Custom",
            isEnabled: true,
            deepLink: "raycast://custom",
            showsPromptSelectorInOverlay: true,
            showsLanguageSelectorInOverlay: false,
        )
        settings.assistantIntegrations = [integration]
        settings.assistantSelectedIntegrationId = integration.id

        let layout = RecordingIndicatorOverlayLayout.resolve(
            renderState: RecordingIndicatorRenderState(
                mode: .recording,
                kind: .assistantIntegration,
                assistantIntegrationID: integration.id,
            ),
            settingsStore: settings,
        )

        XCTAssertEqual(layout.showsPromptSelector, true)
        XCTAssertEqual(layout.showsLanguageSelector, false)
        XCTAssertEqual(layout.showsMeetingTimer, false)
        XCTAssertEqual(layout.auxiliaryControlCount, 1)
    }

    func testAssistantIntegrationLayoutCanShowOnlyLanguageSelector() {
        let integration = AssistantIntegrationConfig(
            id: UUID(),
            name: "Custom",
            isEnabled: true,
            deepLink: "raycast://custom",
            showsPromptSelectorInOverlay: false,
            showsLanguageSelectorInOverlay: true,
        )
        settings.assistantIntegrations = [integration]

        let layout = RecordingIndicatorOverlayLayout.resolve(
            renderState: RecordingIndicatorRenderState(
                mode: .recording,
                kind: .assistantIntegration,
                assistantIntegrationID: integration.id,
            ),
            settingsStore: settings,
        )

        XCTAssertEqual(layout.showsPromptSelector, false)
        XCTAssertEqual(layout.showsLanguageSelector, true)
        XCTAssertEqual(layout.showsMeetingTimer, false)
        XCTAssertEqual(layout.auxiliaryControlCount, 1)
    }

    func testAssistantIntegrationLayoutCanHideBothSelectors() {
        let integration = AssistantIntegrationConfig(
            id: UUID(),
            name: "Custom",
            isEnabled: true,
            deepLink: "raycast://custom",
            showsPromptSelectorInOverlay: false,
            showsLanguageSelectorInOverlay: false,
        )
        settings.assistantIntegrations = [integration]

        let layout = RecordingIndicatorOverlayLayout.resolve(
            renderState: RecordingIndicatorRenderState(
                mode: .recording,
                kind: .assistantIntegration,
                assistantIntegrationID: integration.id,
            ),
            settingsStore: settings,
        )

        XCTAssertEqual(layout.showsPromptSelector, false)
        XCTAssertEqual(layout.showsLanguageSelector, false)
        XCTAssertEqual(layout.showsMeetingTimer, false)
        XCTAssertEqual(layout.auxiliaryControlCount, 0)
    }

    func testAssistantIntegrationLayoutFallsBackWhenIntegrationUnavailable() {
        let layout = RecordingIndicatorOverlayLayout.resolve(
            renderState: RecordingIndicatorRenderState(
                mode: .recording,
                kind: .assistantIntegration,
                assistantIntegrationID: UUID(),
            ),
            settingsStore: settings,
        )

        XCTAssertEqual(layout.showsPromptSelector, false)
        XCTAssertEqual(layout.showsLanguageSelector, false)
        XCTAssertEqual(layout.showsMeetingTimer, false)
        XCTAssertEqual(layout.auxiliaryControlCount, 0)
    }

    func testMeetingLayoutShowsPromptAndTimer() {
        let layout = RecordingIndicatorOverlayLayout.resolve(
            renderState: RecordingIndicatorRenderState(
                mode: .recording,
                kind: .meeting,
                meetingType: .standup,
            ),
            settingsStore: settings,
        )

        XCTAssertEqual(layout.showsPromptSelector, true)
        XCTAssertEqual(layout.showsLanguageSelector, false)
        XCTAssertEqual(layout.showsMeetingTimer, true)
        XCTAssertEqual(layout.auxiliaryControlCount, 1)
    }

    func testNonRecordingModesHideAuxiliaryControls() {
        let integration = AssistantIntegrationConfig(
            id: UUID(),
            name: "Custom",
            isEnabled: true,
            deepLink: "raycast://custom",
            showsPromptSelectorInOverlay: true,
            showsLanguageSelectorInOverlay: true,
        )
        settings.assistantIntegrations = [integration]

        let layout = RecordingIndicatorOverlayLayout.resolve(
            renderState: RecordingIndicatorRenderState(
                mode: .processing,
                kind: .assistantIntegration,
                assistantIntegrationID: integration.id,
            ),
            settingsStore: settings,
        )

        XCTAssertEqual(layout.showsPromptSelector, false)
        XCTAssertEqual(layout.showsLanguageSelector, false)
        XCTAssertEqual(layout.showsMeetingTimer, false)
        XCTAssertEqual(layout.auxiliaryControlCount, 0)
    }
}

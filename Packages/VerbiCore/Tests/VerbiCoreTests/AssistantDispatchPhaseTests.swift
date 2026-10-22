@testable import VerbiCore
@testable import VerbiCoreInfrastructure
@testable import VerbiCoreUI
import XCTest

@MainActor
final class AssistantDispatchPhaseTests: XCTestCase {
    private var phase: AssistantDispatchPhase!
    private var mockRecorder: MockDispatchRecorder!

    override func setUp() async throws {
        try await super.setUp()
        mockRecorder = MockDispatchRecorder()
        phase = AssistantDispatchPhase(
            raycastIntegrationService: mockRecorder,
            textSelectionService: AssistantTextSelectionService(),
            normalizationPhase: AssistantNormalizationPhase(),
        )
    }

    // MARK: - captureSourceText (integration dispatch flow)

    func testCaptureSourceText_IntegrationDispatch_ReturnsCommandAsSource() async throws {
        let (sourceText, result) = try await phase.captureSourceText(
            executionFlow: .integrationDispatch,
            command: "test command",
        )
        XCTAssertEqual(sourceText, "test command")
        XCTAssertNil(result)
    }

    // MARK: - executeDispatch (integration dispatch flow)

    func testExecuteDispatch_IntegrationDispatch_CallsRaycast() async throws {
        let integration = makeIntegrationConfig(
            deepLink: "test://{{assistant_text}}",
        )

        try await phase.executeDispatch(
            executionFlow: .integrationDispatch,
            finalCommand: "final result",
            command: "original",
            processedCommand: "processed",
            selectedIntegration: integration,
            selectedTextResult: nil,
        )

        XCTAssertEqual(mockRecorder.lastCommand, "final result")
        XCTAssertEqual(mockRecorder.lastDeepLink, "test://final result")
    }

    func testExecuteDispatch_IntegrationDispatch_ResolvesShortcodes() async throws {
        let integration = makeIntegrationConfig(
            deepLink: "test://{{assistant_text_urlencoded}}",
        )

        try await phase.executeDispatch(
            executionFlow: .integrationDispatch,
            finalCommand: "hello & world",
            command: "original",
            processedCommand: "processed",
            selectedIntegration: integration,
            selectedTextResult: nil,
        )

        XCTAssertEqual(mockRecorder.lastDeepLink, "test://hello%20%26%20world")
    }

    func testExecuteDispatch_IntegrationDispatch_ThrowsWhenNoIntegration() async {
        do {
            try await phase.executeDispatch(
                executionFlow: .integrationDispatch,
                finalCommand: "test",
                command: "test",
                processedCommand: "test",
                selectedIntegration: nil,
                selectedTextResult: nil,
            )
            XCTFail("Expected error")
        } catch let error as AssistantVoiceCommandError {
            XCTAssertEqual(error, .integrationDisabled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testExecuteDispatch_AssistantMode_ThrowsWhenNoSelection() async {
        do {
            try await phase.executeDispatch(
                executionFlow: .assistantMode,
                finalCommand: "test",
                command: "test",
                processedCommand: "test",
                selectedIntegration: nil,
                selectedTextResult: nil,
            )
            XCTFail("Expected error")
        } catch let error as AssistantVoiceCommandError {
            XCTAssertEqual(error, .noSelectionFound)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

    private func makeIntegrationConfig(deepLink: String = "test://") -> AssistantIntegrationConfig {
        AssistantIntegrationConfig(
            id: UUID(),
            name: "test",
            kind: .deeplink,
            isEnabled: true,
            deepLink: deepLink,
            promptInstructions: nil,
            selectedPreset: nil,
            shortcutDefinition: nil,
            shortcutPresetKey: .notSpecified,
            shortcutActivationMode: .holdOrToggle,
            modifierShortcutGesture: nil,
            advancedScript: nil,
            showsPromptSelectorInOverlay: false,
            showsLanguageSelectorInOverlay: false,
        )
    }
}

@MainActor
private final class MockDispatchRecorder: AssistantDeepLinkDispatching {
    var lastCommand: String?
    var lastDeepLink: String?

    func validateDeepLink(_ value: String) -> AssistantIntegrationDeepLinkValidation {
        .valid
    }

    func dispatch(command: String, baseDeepLink: String) throws -> AssistantIntegrationDispatchResult {
        lastCommand = command
        lastDeepLink = baseDeepLink
        return .openedDeepLink
    }
}

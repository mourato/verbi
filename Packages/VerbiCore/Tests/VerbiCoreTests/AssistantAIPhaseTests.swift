@testable import VerbiCore
@testable import VerbiCoreInfrastructure
@testable import VerbiCoreUI
import XCTest

@MainActor
final class AssistantAIPhaseTests: XCTestCase {

    // MARK: - assistantPromptInstructions

    func testPromptInstructions_IntegrationDispatch_NoBaseInstructions() {
        let phase = makePhase()
        let result = phase.assistantPromptInstructions(
            baseInstructions: nil,
            voiceCommand: "summarize this",
            executionFlow: .integrationDispatch,
        )
        XCTAssertTrue(result.contains("You are preparing text that will be sent to another AI assistant"))
        XCTAssertTrue(result.contains("User command:\nsummarize this"))
        XCTAssertFalse(result.contains("Additional user instructions"))
    }

    func testPromptInstructions_IntegrationDispatch_WithBaseInstructions() {
        let phase = makePhase()
        let result = phase.assistantPromptInstructions(
            baseInstructions: "Be concise",
            voiceCommand: "summarize this",
            executionFlow: .integrationDispatch,
        )
        XCTAssertTrue(result.contains("You are preparing text that will be sent to another AI assistant"))
        XCTAssertTrue(result.contains("Additional user instructions:\nBe concise"))
        XCTAssertTrue(result.contains("User command:\nsummarize this"))
    }

    func testPromptInstructions_AssistantMode_NoBaseInstructions() {
        let phase = makePhase()
        let result = phase.assistantPromptInstructions(
            baseInstructions: nil,
            voiceCommand: "replace with hello",
            executionFlow: .assistantMode,
        )
        XCTAssertEqual(result, "replace with hello")
    }

    func testPromptInstructions_AssistantMode_WithBaseInstructions() {
        let phase = makePhase()
        let result = phase.assistantPromptInstructions(
            baseInstructions: "Translate to French",
            voiceCommand: "hello",
            executionFlow: .assistantMode,
        )
        XCTAssertTrue(result.contains("Translate to French"))
        XCTAssertTrue(result.contains("Comando do usuário:\nhello"))
    }

    func testPromptInstructions_TrimsWhitespace() {
        let phase = makePhase()
        let result = phase.assistantPromptInstructions(
            baseInstructions: nil,
            voiceCommand: "  hello  ",
            executionFlow: .assistantMode,
        )
        XCTAssertEqual(result, "hello")
    }

    // MARK: - normalizedPromptInstructions

    func testNormalizedPromptInstructions_ReturnsInstructionsWhenPresent() {
        let phase = makePhase()
        let integration = makeIntegrationConfig(promptInstructions: "Custom instructions")
        let result = phase.normalizedPromptInstructions(from: integration)
        XCTAssertEqual(result, "Custom instructions")
    }

    func testNormalizedPromptInstructions_ReturnsNilWhenNil() {
        let phase = makePhase()
        let result = phase.normalizedPromptInstructions(from: nil)
        XCTAssertNil(result)
    }

    func testNormalizedPromptInstructions_ReturnsNilWhenEmpty() {
        let phase = makePhase()
        let integration = makeIntegrationConfig(promptInstructions: "  ")
        let result = phase.normalizedPromptInstructions(from: integration)
        XCTAssertNil(result)
    }

    // MARK: - processWithAI

    func testProcessWithAI_AssistantMode_AppliesScriptsAndUsesAssistantModeProcessing() async throws {
        let postProcessingService = MockPostProcessingService()
        let phase = makePhase(postProcessingService: postProcessingService) { script, input, _ in
            switch script {
            case "before":
                "normalized: \(input)"
            case "after":
                "after: \(input)"
            default:
                input
            }
        }

        let result = try await phase.processWithAI(
            sourceText: "source transcript",
            command: " original command ",
            executionFlow: .assistantMode,
            selectedIntegration: makeIntegrationConfig(
                promptInstructions: "Keep it short",
                advancedScript: .init(stage: .beforeAI, script: "before"),
            ),
        )

        XCTAssertEqual(result, "Processed: source transcript")
        XCTAssertEqual(postProcessingService.lastProcessText, "source transcript")
        XCTAssertEqual(postProcessingService.lastMode, .assistant)
        XCTAssertNil(postProcessingService.lastSystemPromptOverride)
        XCTAssertTrue(postProcessingService.lastPromptText?.contains("Keep it short") == true)
        XCTAssertTrue(postProcessingService.lastPromptText?.contains("Comando do usuário:\nnormalized:") == true)
        XCTAssertTrue(postProcessingService.lastPromptText?.contains("original command") == true)
    }

    func testProcessWithAI_IntegrationDispatch_UsesAssistantSystemPrompt() async throws {
        let postProcessingService = MockPostProcessingService()
        let phase = makePhase(postProcessingService: postProcessingService)

        let result = try await phase.processWithAI(
            sourceText: "source transcript",
            command: "summarize this",
            executionFlow: .integrationDispatch,
            selectedIntegration: makeIntegrationConfig(promptInstructions: "Be concise"),
        )

        XCTAssertEqual(result, "Processed: source transcript")
        XCTAssertEqual(postProcessingService.lastSystemPromptOverride, AIPromptTemplates.assistantSystemPrompt)
        XCTAssertTrue(
            postProcessingService.lastPromptText?.contains(
                "You are preparing text that will be sent to another AI assistant",
            ) == true,
        )
        XCTAssertTrue(postProcessingService.lastPromptText?.contains("Additional user instructions:\nBe concise") == true)
    }

    func testProcessWithAI_ThrowsWhenBeforeAIScriptReturnsNil() async {
        let phase = makePhase(postProcessingService: MockPostProcessingService()) { script, _, _ in
            script == "before" ? nil : "unused"
        }

        do {
            _ = try await phase.processWithAI(
                sourceText: "source transcript",
                command: "summarize this",
                executionFlow: .assistantMode,
                selectedIntegration: makeIntegrationConfig(
                    promptInstructions: nil,
                    advancedScript: .init(stage: .beforeAI, script: "before"),
                ),
            )
            XCTFail("Expected processing failure")
        } catch {
            XCTAssertEqual(error as? AssistantVoiceCommandError, .processingFailed)
        }
    }

    // MARK: - Helpers

    private func makePhase(
        postProcessingService: MockPostProcessingService = MockPostProcessingService(),
        runScript: @escaping @Sendable (_ script: String, _ input: String, _ timeoutSeconds: UInt64) async throws -> String? = { _, input, _ in input },
    ) -> AssistantAIPhase {
        AssistantAIPhase(
            postProcessingService: postProcessingService,
            runScript: runScript,
        )
    }

    private func makeIntegrationConfig(
        promptInstructions: String?,
        advancedScript: AssistantIntegrationScriptConfig? = nil,
    ) -> AssistantIntegrationConfig {
        AssistantIntegrationConfig(
            id: UUID(),
            name: "test",
            kind: .deeplink,
            isEnabled: true,
            deepLink: "test://",
            promptInstructions: promptInstructions,
            selectedPreset: nil,
            shortcutDefinition: nil,
            shortcutPresetKey: .notSpecified,
            shortcutActivationMode: .holdOrToggle,
            modifierShortcutGesture: nil,
            advancedScript: advancedScript,
            showsPromptSelectorInOverlay: false,
            showsLanguageSelectorInOverlay: false,
        )
    }
}

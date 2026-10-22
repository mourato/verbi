@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreAI
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import XCTest

@MainActor
final class PostProcessingServiceValidationTests: XCTestCase {
    func testValidateInput_AllowsTranscriptionsOverPreviousCharacterLimit() throws {
        let input = String(repeating: "a", count: 100_001)

        let validated = try PostProcessingService.shared.validateInput(input)

        XCTAssertEqual(validated.count, 100_001)
    }

    func testValidateInput_RejectsEmptyTranscription() {
        XCTAssertThrowsError(try PostProcessingService.shared.validateInput("   \n\t")) { error in
            guard case PostProcessingError.emptyTranscription = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testExplicitRequestUsesFrozenAdapterValuesAfterSettingsMutation() async throws {
        let service = MockPostProcessingService()
        let adapter = PostProcessingRepositoryAdapter(postProcessingService: service)
        let prompt = DomainPostProcessingPrompt(title: "Frozen", content: "Use only this prompt")
        let selection = DomainPostProcessingSelection(
            providerID: LLMProvider.anthropic.rawValue,
            modelID: "claude-frozen",
            registrationID: nil,
        )
        let configuration = DomainPostProcessingConfiguration(
            providerID: LLMProvider.anthropic.rawValue,
            baseURL: "https://frozen.example/v1",
            modelID: "claude-frozen",
            readinessIssue: nil,
            outputLanguageID: DictationOutputLanguage.portuguese.rawValue,
        )
        let request = DomainPostProcessingRequest(
            prompt: prompt,
            mode: .assistant,
            selection: selection,
            configuration: configuration,
            useStructuredPipeline: false,
            systemPromptOverride: "Frozen system prompt",
        )
        let settings = AppSettingsStore.shared
        let originalSelection = settings.enhancementsDictationAISelection
        let originalLanguage = settings.meetingSummaryOutputLanguage
        defer {
            settings.enhancementsDictationAISelection = originalSelection
            settings.meetingSummaryOutputLanguage = originalLanguage
        }

        settings.enhancementsDictationAISelection = EnhancementsAISelection(
            provider: .openai,
            selectedModel: "mutated-model",
        )
        settings.meetingSummaryOutputLanguage = .english
        _ = try await adapter.processTranscription("source", request: request)

        let captured = try XCTUnwrap(service.lastRequest)
        XCTAssertEqual(captured.mode, .assistant)
        XCTAssertEqual(captured.prompt?.promptText, "Use only this prompt")
        XCTAssertEqual(captured.selection, EnhancementsAISelection(
            provider: .anthropic,
            selectedModel: "claude-frozen",
        ))
        XCTAssertEqual(captured.configuration.provider, .anthropic)
        XCTAssertEqual(captured.configuration.baseURL, "https://frozen.example/v1")
        XCTAssertEqual(captured.configuration.selectedModel, "claude-frozen")
        XCTAssertEqual(captured.outputLanguageID, DictationOutputLanguage.portuguese.rawValue)
        XCTAssertFalse(captured.useStructuredPipeline)
        XCTAssertEqual(captured.systemPromptOverride, "Frozen system prompt")
    }

    func testExplicitServiceUsesRequestReadinessSnapshot() async throws {
        let request = PostProcessingRequest(
            prompt: .defaultPrompt,
            mode: .meeting,
            selection: EnhancementsAISelection(provider: .openai, selectedModel: "frozen-model"),
            configuration: AIConfiguration(
                provider: .openai,
                baseURL: "https://frozen.example/v1",
                selectedModel: "frozen-model",
            ),
            readinessIssue: "enhancements.missing_model",
            useStructuredPipeline: true,
        )

        do {
            _ = try await PostProcessingService.shared.processTranscription("source", request: request)
            XCTFail("Expected the frozen readiness snapshot to block execution")
        } catch let error as PostProcessingError {
            guard case .configurationNotReady = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testAdapterRejectsUnknownProviderWithoutOpenAIFallback() async throws {
        let service = MockPostProcessingService()
        let adapter = PostProcessingRepositoryAdapter(postProcessingService: service)
        let request = DomainPostProcessingRequest(
            mode: .meeting,
            configuration: DomainPostProcessingConfiguration(
                providerID: "provider-not-registered",
                baseURL: "https://invalid.example/v1",
                modelID: "model",
            ),
            useStructuredPipeline: false,
        )

        do {
            _ = try await adapter.processTranscription("source", request: request)
            XCTFail("Expected unknown provider to be rejected")
        } catch let error as PostProcessingError {
            guard case .configurationNotReady = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }
}

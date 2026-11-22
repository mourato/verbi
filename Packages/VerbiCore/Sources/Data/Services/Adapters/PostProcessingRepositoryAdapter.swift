import Foundation
import VerbiCoreDomain
import VerbiCoreInfrastructure

@MainActor
public final class PostProcessingRepositoryAdapter: PostProcessingRepository {
    private let postProcessingService: any PostProcessingServiceProtocol

    public init(postProcessingService: any PostProcessingServiceProtocol) {
        self.postProcessingService = postProcessingService
    }

    public func processTranscription(
        _ transcription: String,
        request: DomainPostProcessingRequest
    ) async throws -> String {
        try await postProcessingService.processTranscription(
            transcription,
            request: makeServiceRequest(from: request)
        )
    }

    public func processTranscriptionStructured(
        _ transcription: String,
        request: DomainPostProcessingRequest
    ) async throws -> DomainPostProcessingResult {
        try await postProcessingService.processTranscriptionStructured(
            transcription,
            request: makeServiceRequest(from: request)
        )
    }

    private func makeServiceRequest(from request: DomainPostProcessingRequest) throws -> PostProcessingRequest {
        let provider = try aiProvider(
            id: request.configuration.providerID,
            mode: request.mode
        )
        let selection = try request.selection.map { try toAISelection($0, mode: request.mode) }
        let prompt = request.prompt.map {
            PostProcessingPrompt(id: $0.id, title: $0.title, promptText: $0.content, isActive: true)
        }
        return PostProcessingRequest(
            prompt: prompt,
            mode: request.mode,
            selection: selection,
            configuration: AIConfiguration(
                provider: provider,
                baseURL: request.configuration.baseURL,
                selectedModel: request.configuration.modelID
            ),
            readinessIssue: request.configuration.readinessIssue,
            outputLanguageID: request.configuration.outputLanguageID,
            useStructuredPipeline: request.useStructuredPipeline,
            systemPromptOverride: request.systemPromptOverride
        )
    }

    private func toAISelection(
        _ selection: DomainPostProcessingSelection,
        mode: CaptureMode
    ) throws -> EnhancementsAISelection {
        let provider = try aiProvider(id: selection.providerID, mode: mode)
        return EnhancementsAISelection(
            provider: provider,
            selectedModel: selection.modelID,
            registrationID: selection.registrationID
        )
    }

    private func aiProvider(id: String, mode: CaptureMode) throws -> LLMProvider {
        guard let provider = LLMProvider(rawValue: id) else {
            throw PostProcessingError.configurationNotReady(
                reason: "enhancements.invalid_provider",
                modeName: mode.rawValue
            )
        }
        return provider
    }
}

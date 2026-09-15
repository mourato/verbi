// PostProcessingRepositoryAdapter - Adapter para PostProcessingRepository usando PostProcessingService
// Seguindo Clean Architecture

import Foundation
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

/// Adapter que implementa PostProcessingRepository usando PostProcessingService existente
@MainActor
public final class PostProcessingRepositoryAdapter: PostProcessingRepository {
    private let postProcessingService: any PostProcessingServiceProtocol
    /// Compatibility-only fallback for legacy overloads; explicit requests never use this store.
    private let settings: AppSettingsStore

    public init(postProcessingService: any PostProcessingServiceProtocol) {
        self.postProcessingService = postProcessingService
        settings = .shared
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
        mode: IntelligenceKernelMode
    ) throws -> EnhancementsAISelection {
        let provider = try aiProvider(id: selection.providerID, mode: mode)
        return EnhancementsAISelection(
            provider: provider,
            selectedModel: selection.modelID,
            registrationID: selection.registrationID
        )
    }

    private func aiProvider(id: String, mode: IntelligenceKernelMode) throws -> AIProvider {
        guard let provider = AIProvider(rawValue: id) else {
            throw PostProcessingError.configurationNotReady(
                reason: "enhancements.invalid_provider",
                modeName: mode.rawValue
            )
        }
        return provider
    }

    public func processTranscription(_ transcription: String) async throws -> String {
        try await postProcessingService.processTranscription(transcription)
    }

    public func processTranscription(
        _ transcription: String,
        mode: IntelligenceKernelMode
    ) async throws -> String {
        if let prompt = selectedPrompt(for: mode) {
            return try await postProcessingService.processTranscription(
                transcription,
                with: prompt,
                mode: mode,
                systemPromptOverride: nil
            )
        }

        return try await postProcessingService.processTranscription(transcription)
    }

    public func processTranscription(
        _ transcription: String,
        with prompt: DomainPostProcessingPrompt
    ) async throws -> String {
        // Converter DomainPostProcessingPrompt para PostProcessingPrompt (legado)
        let legacyPrompt = PostProcessingPrompt(
            id: prompt.id,
            title: prompt.title,
            promptText: prompt.content,
            isActive: true
        )
        return try await postProcessingService.processTranscription(transcription, with: legacyPrompt)
    }

    public func processTranscription(
        _ transcription: String,
        with prompt: DomainPostProcessingPrompt,
        mode: IntelligenceKernelMode
    ) async throws -> String {
        let legacyPrompt = PostProcessingPrompt(
            id: prompt.id,
            title: prompt.title,
            promptText: prompt.content,
            isActive: true
        )
        return try await postProcessingService.processTranscription(
            transcription,
            with: legacyPrompt,
            mode: mode,
            systemPromptOverride: nil
        )
    }

    public func processTranscriptionStructured(_ transcription: String) async throws -> DomainPostProcessingResult {
        try await postProcessingService.processTranscriptionStructured(transcription)
    }

    public func processTranscriptionStructured(
        _ transcription: String,
        mode: IntelligenceKernelMode
    ) async throws -> DomainPostProcessingResult {
        if let prompt = selectedPrompt(for: mode) {
            return try await postProcessingService.processTranscriptionStructured(
                transcription,
                with: prompt,
                mode: mode
            )
        }

        return try await postProcessingService.processTranscriptionStructured(transcription)
    }

    public func processTranscriptionStructured(
        _ transcription: String,
        with prompt: DomainPostProcessingPrompt
    ) async throws -> DomainPostProcessingResult {
        let legacyPrompt = PostProcessingPrompt(
            id: prompt.id,
            title: prompt.title,
            promptText: prompt.content,
            isActive: true
        )
        return try await postProcessingService.processTranscriptionStructured(transcription, with: legacyPrompt)
    }

    public func processTranscriptionStructured(
        _ transcription: String,
        with prompt: DomainPostProcessingPrompt,
        mode: IntelligenceKernelMode
    ) async throws -> DomainPostProcessingResult {
        let legacyPrompt = PostProcessingPrompt(
            id: prompt.id,
            title: prompt.title,
            promptText: prompt.content,
            isActive: true
        )
        return try await postProcessingService.processTranscriptionStructured(
            transcription,
            with: legacyPrompt,
            mode: mode
        )
    }

    private func selectedPrompt(for mode: IntelligenceKernelMode) -> PostProcessingPrompt? {
        switch mode {
        case .meeting:
            settings.selectedPrompt
        case .dictation, .assistant:
            settings.selectedDictationPrompt ?? .defaultPrompt
        }
    }
}

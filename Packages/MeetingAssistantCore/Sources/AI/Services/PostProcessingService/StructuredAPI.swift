import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

extension PostProcessingService {
    struct StructuredRequestContext {
        let transcription: String
        let prompt: PostProcessingPrompt
        let mode: IntelligenceKernelMode
        let selectionOverride: EnhancementsAISelection?
        let systemPromptOverride: String?
        let requestProfile: RequestProfile
        let requestConfig: AIConfiguration
        let traceContext: RequestTraceContext
        let startedAt: Date
    }

    // MARK: - Public API (Structured)

    public func processTranscriptionStructured(
        _ transcription: String,
        request: PostProcessingRequest
    ) async throws -> DomainPostProcessingResult {
        guard let prompt = request.prompt else {
            return try await processTranscriptionStructured(
                transcription,
                with: .defaultPrompt,
                request: request
            )
        }
        return try await processTranscriptionStructured(transcription, with: prompt, request: request)
    }

    private func processTranscriptionStructured(
        _ transcription: String,
        with prompt: PostProcessingPrompt,
        request: PostProcessingRequest
    ) async throws -> DomainPostProcessingResult {
        if !request.useStructuredPipeline {
            let text = try await processTranscription(transcription, request: request)
            return summaryFallbackBuilder.build(providerOutput: text, transcription: transcription)
        }
        _ = try validateInput(transcription)
        guard request.readinessIssue == nil else {
            throw unavailableConfigurationError(
                mode: request.mode,
                message: "Structured post-processing blocked: enhancements configuration not ready",
                reasonCode: request.readinessIssue
            )
        }
        let context = makeStructuredRequestContext(
            transcription: transcription,
            prompt: prompt,
            mode: request.mode,
            selectionOverride: request.selection,
            systemPromptOverride: request.systemPromptOverride,
            requestConfig: request.configuration,
            useLiveSettings: false,
            outputLanguageID: request.outputLanguageID
        )
        return try await executeStructuredRequest(context: context)
    }

    private func executeStructuredRequest(context: StructuredRequestContext) async throws -> DomainPostProcessingResult {
        isProcessing = true
        lastError = nil
        defer {
            isProcessing = false
            reportDictationPostProcessingDurationIfNeeded(mode: context.mode, startedAt: context.startedAt)
        }
        do {
            let result = try await sendToAIStructured(
                transcription: context.transcription,
                prompt: context.prompt,
                mode: context.mode,
                selectionOverride: context.selectionOverride,
                systemPromptOverride: context.systemPromptOverride,
                requestProfile: context.requestProfile,
                requestConfig: context.requestConfig,
                traceContext: context.traceContext
            )
            let metadata = TranscriptionOutputSanitizer.extractContextMetadata(fromPromptInput: context.transcription)
            return sanitizeStructuredResult(result, transcription: context.transcription, contextMetadata: metadata)
        } catch {
            return try await handleStructuredFailure(context: context, error: error)
        }
    }

    public func processTranscriptionStructured(_ transcription: String) async throws -> DomainPostProcessingResult {
        guard settings.postProcessingEnabled else {
            let fallback = summaryFallbackBuilder.build(providerOutput: "", transcription: transcription)
            AppLogger.info(
                "Post-processing disabled, returning deterministic structured fallback",
                category: .transcriptionEngine
            )
            return fallback
        }

        guard let prompt = settings.selectedPrompt else {
            throw PostProcessingError.noPromptSelected
        }

        return try await processTranscriptionStructured(transcription, with: prompt)
    }

    public func processTranscriptionStructured(
        _ transcription: String,
        with prompt: PostProcessingPrompt
    ) async throws -> DomainPostProcessingResult {
        try await processTranscriptionStructured(
            transcription,
            with: prompt,
            mode: .meeting,
            systemPromptOverride: nil
        )
    }

    public func processTranscriptionStructured(
        _ transcription: String,
        with prompt: PostProcessingPrompt,
        mode: IntelligenceKernelMode
    ) async throws -> DomainPostProcessingResult {
        try await processTranscriptionStructured(
            transcription,
            with: prompt,
            mode: mode,
            systemPromptOverride: nil
        )
    }

    func processTranscriptionStructured(
        _ transcription: String,
        with prompt: PostProcessingPrompt,
        mode: IntelligenceKernelMode,
        systemPromptOverride: String?
    ) async throws -> DomainPostProcessingResult {
        try await processTranscriptionStructured(
            transcription,
            with: prompt,
            mode: mode,
            selectionOverride: nil,
            systemPromptOverride: systemPromptOverride
        )
    }

    public func processTranscriptionStructured(
        _ transcription: String,
        with prompt: PostProcessingPrompt,
        mode: IntelligenceKernelMode,
        selectionOverride: EnhancementsAISelection
    ) async throws -> DomainPostProcessingResult {
        try await processTranscriptionStructured(
            transcription,
            with: prompt,
            mode: mode,
            selectionOverride: Optional(selectionOverride),
            systemPromptOverride: nil
        )
    }

    // swiftlint:disable:next function_body_length
    private func processTranscriptionStructured(
        _ transcription: String,
        with prompt: PostProcessingPrompt,
        mode: IntelligenceKernelMode,
        selectionOverride: EnhancementsAISelection?,
        systemPromptOverride: String?,
        requestConfig: AIConfiguration? = nil,
        useLiveSettings: Bool = true
    ) async throws -> DomainPostProcessingResult {
        _ = try validateInput(transcription)
        let readinessIssue = useLiveSettings
            ? (selectionOverride.map {
                settings.enhancementsInferenceReadinessIssue(for: $0, apiKeyExists: nil)
            } ?? settings.enhancementsInferenceReadinessIssue(for: mode, apiKeyExists: nil))
            : nil
        guard readinessIssue == nil else {
            throw unavailableConfigurationError(
                mode: mode,
                message: "Structured post-processing blocked: enhancements configuration not ready"
            )
        }

        let context = makeStructuredRequestContext(
            transcription: transcription,
            prompt: prompt,
            mode: mode,
            selectionOverride: selectionOverride,
            systemPromptOverride: systemPromptOverride,
            requestConfig: requestConfig,
            useLiveSettings: useLiveSettings
        )

        if !context.requestProfile.useStructuredPipeline {
            return try await runFastStructuredFallback(from: context)
        }

        isProcessing = true
        lastError = nil
        defer {
            isProcessing = false
            reportDictationPostProcessingDurationIfNeeded(mode: mode, startedAt: context.startedAt)
        }

        do {
            let result = try await sendToAIStructured(
                transcription: context.transcription,
                prompt: context.prompt,
                mode: context.mode,
                selectionOverride: context.selectionOverride,
                systemPromptOverride: context.systemPromptOverride,
                requestProfile: context.requestProfile,
                requestConfig: context.requestConfig,
                traceContext: context.traceContext
            )

            AppLogger.info(
                "Structured post-processing completed",
                category: .transcriptionEngine,
                extra: traceExtra(
                    from: context.traceContext,
                    attempt: 1,
                    elapsedMilliseconds: Date().timeIntervalSince(context.startedAt) * 1000,
                    extra: ["output_state": result.outputState.rawValue]
                )
            )
            let mergedContextMetadata = TranscriptionOutputSanitizer.extractContextMetadata(
                fromPromptInput: context.transcription
            )
            return sanitizeStructuredResult(
                result,
                transcription: context.transcription,
                contextMetadata: mergedContextMetadata
            )
        } catch {
            return try await handleStructuredFailure(context: context, error: error)
        }
    }

    private func makeStructuredRequestContext(
        transcription: String,
        prompt: PostProcessingPrompt,
        mode: IntelligenceKernelMode,
        selectionOverride: EnhancementsAISelection?,
        systemPromptOverride: String?,
        requestConfig explicitRequestConfig: AIConfiguration? = nil,
        useLiveSettings: Bool = true,
        outputLanguageID: String? = nil
    ) -> StructuredRequestContext {
        let requestProfile = profile(
            for: mode,
            prefersStructuredPipeline: true,
            useLiveSettings: useLiveSettings,
            outputLanguageID: outputLanguageID
        )
        let requestConfig: AIConfiguration = if let explicitRequestConfig {
            explicitRequestConfig
        } else if useLiveSettings {
            selectionOverride.map {
                settings.resolvedEnhancementsAIConfiguration(for: $0)
            } ?? settings.resolvedEnhancementsAIConfiguration(for: mode)
        } else {
            preconditionFailure("Explicit post-processing routes require request configuration")
        }
        let traceContext = makeTraceContext(
            mode: mode,
            provider: requestConfig.provider,
            model: requestConfig.selectedModel,
            prompt: prompt,
            pipeline: requestProfile.pipeline
        )

        return StructuredRequestContext(
            transcription: transcription,
            prompt: prompt,
            mode: mode,
            selectionOverride: selectionOverride,
            systemPromptOverride: systemPromptOverride,
            requestProfile: requestProfile,
            requestConfig: requestConfig,
            traceContext: traceContext,
            startedAt: Date()
        )
    }

    private func runFastStructuredFallback(from context: StructuredRequestContext) async throws -> DomainPostProcessingResult {
        let fastResult = try await processTranscription(
            context.transcription,
            request: PostProcessingRequest(
                prompt: context.prompt,
                mode: context.mode,
                selection: context.selectionOverride,
                configuration: context.requestConfig,
                outputLanguageID: context.requestProfile.outputLanguageID,
                useStructuredPipeline: false,
                systemPromptOverride: context.systemPromptOverride
            )
        )
        // Keep processedText and canonicalSummary on the same fallback contract.
        return summaryFallbackBuilder.build(
            providerOutput: fastResult,
            transcription: context.transcription
        )
    }

    private func handleStructuredFailure(
        context: StructuredRequestContext,
        error: Error
    ) async throws -> DomainPostProcessingResult {
        let processingError = normalizePostProcessingError(error)

        guard shouldTriggerDictationTimeoutFallback(for: context.mode, error: processingError) else {
            lastError = processingError
            throw processingError
        }

        reportDictationFallbackMetrics()

        AppLogger.warning(
            "Structured dictation timed out; running fast fallback",
            category: .transcriptionEngine,
            extra: traceExtra(
                from: context.traceContext,
                attempt: 1,
                elapsedMilliseconds: Date().timeIntervalSince(context.startedAt) * 1000
            )
        )

        return try await runStructuredFallback(from: context)
    }

    private func runStructuredFallback(from context: StructuredRequestContext) async throws -> DomainPostProcessingResult {
        let fallbackProfile = dictationFallbackProfile()
        let fallbackPrompt = PostProcessingPrompt.defaultPrompt
        let fallbackTraceContext = makeTraceContext(
            mode: context.mode,
            provider: context.requestConfig.provider,
            model: context.requestConfig.selectedModel,
            prompt: fallbackPrompt,
            pipeline: fallbackProfile.pipeline
        )

        do {
            let fallbackText = try await sendToAI(
                transcription: context.transcription,
                prompt: fallbackPrompt,
                mode: context.mode,
                selectionOverride: context.selectionOverride,
                systemPromptOverride: context.systemPromptOverride,
                requestProfile: fallbackProfile,
                requestConfig: context.requestConfig,
                traceContext: fallbackTraceContext
            )
            let mergedContextMetadata = TranscriptionOutputSanitizer.extractContextMetadata(
                fromPromptInput: context.transcription
            )
            let sanitizedFallback = TranscriptionOutputSanitizer.sanitize(
                processedContent: fallbackText,
                contextMetadata: mergedContextMetadata
            )
            let baseTranscriptionText = TranscriptionOutputSanitizer.stripPromptMetadata(from: context.transcription)
            let resolvedFallbackText = sanitizedFallback.text ?? (baseTranscriptionText.isEmpty ? context.transcription : baseTranscriptionText)
            return summaryFallbackBuilder.build(
                providerOutput: resolvedFallbackText,
                transcription: context.transcription
            )
        } catch {
            let fallbackError = normalizePostProcessingError(error)
            lastError = fallbackError
            throw fallbackError
        }
    }

    private func sanitizeStructuredResult(
        _ result: DomainPostProcessingResult,
        transcription: String,
        contextMetadata: String?
    ) -> DomainPostProcessingResult {
        let baseTranscriptionText = TranscriptionOutputSanitizer.stripPromptMetadata(from: transcription)
        let resolvedBaseText = baseTranscriptionText.isEmpty ? transcription : baseTranscriptionText
        let sanitized = TranscriptionOutputSanitizer.sanitize(
            processedContent: result.processedText,
            contextMetadata: contextMetadata
        )

        guard sanitized.text != result.processedText else {
            return result
        }

        if let sanitizedText = sanitized.text {
            AppLogger.warning(
                "Structured post-processing output sanitized after reserved metadata block detection",
                category: .transcriptionEngine
            )
            return DomainPostProcessingResult(
                processedText: sanitizedText,
                canonicalSummary: result.canonicalSummary,
                outputState: result.outputState
            )
        }

        AppLogger.warning(
            "Structured post-processing output discarded due to context leakage; using deterministic fallback text",
            category: .transcriptionEngine
        )

        let fallbackSummary = summaryFallbackBuilder.build(
            providerOutput: resolvedBaseText,
            transcription: transcription
        )
        return DomainPostProcessingResult(
            processedText: resolvedBaseText,
            canonicalSummary: fallbackSummary.canonicalSummary,
            outputState: .deterministicFallback
        )
    }
}

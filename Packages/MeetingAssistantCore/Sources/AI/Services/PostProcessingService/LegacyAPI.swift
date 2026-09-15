import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

public extension PostProcessingService {
    func processTranscription(
        _ transcription: String,
        request: PostProcessingRequest
    ) async throws -> String {
        let prompt = request.prompt ?? .defaultPrompt
        _ = try validateInput(transcription)
        guard request.readinessIssue == nil else {
            throw unavailableConfigurationError(
                mode: request.mode,
                message: "Post-processing blocked: enhancements configuration not ready",
                reasonCode: request.readinessIssue
            )
        }
        let context = makeLegacyRequestContext(
            transcription: transcription,
            prompt: prompt,
            mode: request.mode,
            selectionOverride: request.selection,
            systemPromptOverride: request.systemPromptOverride,
            requestConfig: request.configuration,
            useLiveSettings: false,
            outputLanguageID: request.outputLanguageID
        )
        isProcessing = true
        lastError = nil
        defer {
            isProcessing = false
            reportDictationPostProcessingDurationIfNeeded(mode: context.mode, startedAt: context.startedAt)
        }
        do {
            return try await performLegacyAIRequest(context: context)
        } catch {
            return try await handleLegacyFailure(context: context, error: error)
        }
    }

    // MARK: - Public API (Legacy String)

    /// Processes a transcription using the currently selected prompt.
    /// - Parameter transcription: The raw transcription text.
    /// - Returns: The processed text from the AI.
    func processTranscription(_ transcription: String) async throws -> String {
        guard settings.postProcessingEnabled else {
            AppLogger.info("Post-processing disabled, skipping", category: .transcriptionEngine)
            return transcription
        }

        guard let prompt = settings.selectedPrompt else {
            throw PostProcessingError.noPromptSelected
        }

        return try await processTranscription(transcription, with: prompt)
    }

    /// Processes a transcription using a specific prompt.
    /// - Parameters:
    ///   - transcription: The raw transcription text.
    ///   - prompt: The prompt to use for processing.
    /// - Returns: The processed text from the AI.
    func processTranscription(
        _ transcription: String,
        with prompt: PostProcessingPrompt
    ) async throws -> String {
        try await processTranscription(
            transcription,
            with: prompt,
            mode: .meeting,
            systemPromptOverride: nil
        )
    }

    func processTranscription(
        _ transcription: String,
        with prompt: PostProcessingPrompt,
        systemPromptOverride: String?
    ) async throws -> String {
        try await processTranscription(
            transcription,
            with: prompt,
            mode: .meeting,
            systemPromptOverride: systemPromptOverride
        )
    }

    func processTranscription(
        _ transcription: String,
        with prompt: PostProcessingPrompt,
        mode: IntelligenceKernelMode,
        systemPromptOverride: String?
    ) async throws -> String {
        try await processTranscription(
            transcription,
            with: prompt,
            mode: mode,
            selectionOverride: nil,
            systemPromptOverride: systemPromptOverride
        )
    }

    func processTranscription(
        _ transcription: String,
        with prompt: PostProcessingPrompt,
        mode: IntelligenceKernelMode,
        selectionOverride: EnhancementsAISelection,
        systemPromptOverride: String?
    ) async throws -> String {
        try await processTranscription(
            transcription,
            with: prompt,
            mode: mode,
            selectionOverride: Optional(selectionOverride),
            systemPromptOverride: systemPromptOverride
        )
    }
}

extension PostProcessingService {
    struct LegacyRequestContext {
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

    func processTranscription(
        _ transcription: String,
        with prompt: PostProcessingPrompt,
        mode: IntelligenceKernelMode,
        selectionOverride: EnhancementsAISelection?,
        systemPromptOverride: String?,
        requestConfig: AIConfiguration? = nil,
        useLiveSettings: Bool = true
    ) async throws -> String {
        _ = try validateInput(transcription)
        let readinessIssue = useLiveSettings
            ? (selectionOverride.map {
                settings.enhancementsInferenceReadinessIssue(for: $0, apiKeyExists: nil)
            } ?? settings.enhancementsInferenceReadinessIssue(for: mode, apiKeyExists: nil))
            : nil
        guard readinessIssue == nil else {
            throw unavailableConfigurationError(
                mode: mode,
                message: "Post-processing blocked: enhancements configuration not ready"
            )
        }

        let context = makeLegacyRequestContext(
            transcription: transcription,
            prompt: prompt,
            mode: mode,
            selectionOverride: selectionOverride,
            systemPromptOverride: systemPromptOverride,
            requestConfig: requestConfig,
            useLiveSettings: useLiveSettings
        )

        isProcessing = true
        lastError = nil
        defer {
            isProcessing = false
            reportDictationPostProcessingDurationIfNeeded(mode: mode, startedAt: context.startedAt)
        }

        do {
            return try await performLegacyAIRequest(context: context)
        } catch {
            return try await handleLegacyFailure(context: context, error: error)
        }
    }

    private func performLegacyAIRequest(context: LegacyRequestContext) async throws -> String {
        let result = try await sendToAI(
            transcription: context.transcription,
            prompt: context.prompt,
            mode: context.mode,
            selectionOverride: context.selectionOverride,
            systemPromptOverride: context.systemPromptOverride,
            requestProfile: context.requestProfile,
            requestConfig: context.requestConfig,
            traceContext: context.traceContext
        )
        let fallbackText = TranscriptionOutputSanitizer.stripPromptMetadata(from: context.transcription)
        let sanitizedResult = TranscriptionOutputSanitizer.sanitize(
            processedContent: result,
            contextMetadata: TranscriptionOutputSanitizer.extractContextMetadata(fromPromptInput: context.transcription)
        )

        if sanitizedResult.contextLeakDetected {
            AppLogger.warning(
                "Post-processing output discarded due to context leakage; using raw transcription fallback",
                category: .transcriptionEngine
            )
            return fallbackText.isEmpty ? context.transcription : fallbackText
        }

        if sanitizedResult.removedReservedBlocks {
            AppLogger.warning(
                "Post-processing output sanitized after reserved metadata block detection",
                category: .transcriptionEngine
            )
        }

        logRequestSuccess(message: "Post-processing completed", context: context.traceContext, startedAt: context.startedAt)
        return sanitizedResult.text.flatMap { $0.isEmpty ? nil : $0 }
            ?? (fallbackText.isEmpty ? context.transcription : fallbackText)
    }

    private func makeLegacyRequestContext(
        transcription: String,
        prompt: PostProcessingPrompt,
        mode: IntelligenceKernelMode,
        selectionOverride: EnhancementsAISelection?,
        systemPromptOverride: String?,
        requestConfig explicitRequestConfig: AIConfiguration? = nil,
        useLiveSettings: Bool = true,
        outputLanguageID: String? = nil
    ) -> LegacyRequestContext {
        let requestProfile = profile(
            for: mode,
            prefersStructuredPipeline: false,
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

        return LegacyRequestContext(
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

    private func handleLegacyFailure(context: LegacyRequestContext, error: Error) async throws -> String {
        let processingError = normalizePostProcessingError(error)

        guard shouldTriggerDictationTimeoutFallback(for: context.mode, error: processingError) else {
            lastError = processingError
            throw processingError
        }

        reportDictationFallbackMetrics()

        AppLogger.warning(
            "Dictation post-processing timed out; running fast fallback",
            category: .transcriptionEngine,
            extra: traceExtra(
                from: context.traceContext,
                attempt: 1,
                elapsedMilliseconds: Date().timeIntervalSince(context.startedAt) * 1000
            )
        )

        return try await runLegacyFallback(from: context)
    }

    private func runLegacyFallback(from context: LegacyRequestContext) async throws -> String {
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
            return try await sendToAI(
                transcription: context.transcription,
                prompt: fallbackPrompt,
                mode: context.mode,
                selectionOverride: context.selectionOverride,
                systemPromptOverride: nil,
                requestProfile: fallbackProfile,
                requestConfig: context.requestConfig,
                traceContext: fallbackTraceContext
            )
        } catch {
            let fallbackError = normalizePostProcessingError(error)
            lastError = fallbackError
            throw fallbackError
        }
    }

    func unavailableConfigurationError(
        mode: IntelligenceKernelMode,
        message: String,
        reasonCode explicitReasonCode: String? = nil
    ) -> PostProcessingError {
        let reasonCode = explicitReasonCode ?? settings
            .enhancementsInferenceReadinessIssue(for: mode, apiKeyExists: nil)?
            .rawValue ?? "enhancements.not_ready"
        AppLogger.info(message, category: .transcriptionEngine, extra: ["reasonCode": reasonCode])
        return .configurationNotReady(reason: reasonCode, modeName: mode.displayName)
    }

    private func logRequestSuccess(message: String, context: RequestTraceContext, startedAt: Date) {
        AppLogger.info(
            message,
            category: .transcriptionEngine,
            extra: traceExtra(
                from: context,
                attempt: 1,
                elapsedMilliseconds: Date().timeIntervalSince(startedAt) * 1000
            )
        )
    }

    func reportDictationFallbackMetrics() {
        PerformanceMonitor.shared.reportMetric(name: "dictation_timeout_count", value: 1, unit: "count")
        PerformanceMonitor.shared.reportMetric(name: "dictation_fallback_triggered", value: 1, unit: "count")
    }
}

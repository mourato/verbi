import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

extension PostProcessingService {
    // MARK: - Shared Validation & Tracing

    func validateInput(_ transcription: String) throws -> String {
        let trimmedTranscription = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscription.isEmpty else {
            throw PostProcessingError.emptyTranscription
        }

        return trimmedTranscription
    }

    func profile(
        for mode: IntelligenceKernelMode,
        prefersStructuredPipeline: Bool,
        useLiveSettings: Bool = true,
        outputLanguageID: String? = nil
    ) -> RequestProfile {
        let resolvedOutputLanguageID = outputLanguageID ?? (useLiveSettings && mode == .meeting ? settings.meetingSummaryOutputLanguage.rawValue : nil)
        switch mode {
        case .meeting:
            return RequestProfile(
                name: "meetingProfile",
                timeoutSeconds: Constants.meetingRequestTimeoutSeconds,
                retryCount: Constants.meetingRetryCount,
                useStructuredPipeline: prefersStructuredPipeline,
                useRepair: prefersStructuredPipeline,
                pipeline: prefersStructuredPipeline ? "structured" : "fast",
                useLiveSettings: useLiveSettings,
                outputLanguageID: resolvedOutputLanguageID
            )
        case .dictation, .assistant:
            let canUseStructured = prefersStructuredPipeline && (!useLiveSettings || settings.dictationStructuredPostProcessingEnabled)
            return RequestProfile(
                name: "dictationProfile",
                timeoutSeconds: Constants.dictationRequestTimeoutSeconds,
                retryCount: 0,
                useStructuredPipeline: canUseStructured,
                useRepair: canUseStructured,
                pipeline: canUseStructured ? "structured" : "fast",
                useLiveSettings: useLiveSettings,
                outputLanguageID: resolvedOutputLanguageID
            )
        }
    }

    func dictationFallbackProfile() -> RequestProfile {
        RequestProfile(
            name: "dictationFallbackProfile",
            timeoutSeconds: Constants.dictationFallbackTimeoutSeconds,
            retryCount: 0,
            useStructuredPipeline: false,
            useRepair: false,
            pipeline: "fast",
            useLiveSettings: false,
            outputLanguageID: nil
        )
    }

    func makeTraceContext(
        mode: IntelligenceKernelMode,
        provider: AIProvider,
        model: String,
        prompt: PostProcessingPrompt,
        pipeline: String
    ) -> RequestTraceContext {
        RequestTraceContext(
            mode: mode,
            provider: provider,
            model: model,
            promptId: prompt.id.uuidString,
            promptTitle: prompt.title,
            pipeline: pipeline
        )
    }

    func traceExtra(
        from context: RequestTraceContext,
        attempt: Int,
        elapsedMilliseconds: Double?,
        extra: [String: Any] = [:]
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "mode": context.mode.rawValue,
            "provider": context.provider.rawValue,
            "model": context.model,
            "promptId": context.promptId,
            "promptTitle": context.promptTitle,
            "pipeline": context.pipeline,
            "attempt": attempt
        ]

        if let elapsedMilliseconds {
            payload["elapsed_ms"] = elapsedMilliseconds
        }

        for (key, value) in extra {
            payload[key] = value
        }

        return payload
    }

    func normalizePostProcessingError(_ error: Error) -> PostProcessingError {
        if let error = error as? PostProcessingError {
            return error
        }

        return .requestFailed(error)
    }

    func shouldTriggerDictationTimeoutFallback(
        for mode: IntelligenceKernelMode,
        error: PostProcessingError
    ) -> Bool {
        mode == .dictation && isTimeoutError(error)
    }

    func isTimeoutError(_ error: Error) -> Bool {
        if case let PostProcessingError.requestFailed(underlyingError) = error {
            return isTimeoutError(underlyingError)
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
    }

    func reportDictationPostProcessingDurationIfNeeded(
        mode: IntelligenceKernelMode,
        startedAt: Date
    ) {
        guard mode == .dictation else { return }

        PerformanceMonitor.shared.reportMetric(
            name: "dictation_post_processing_ms",
            value: Date().timeIntervalSince(startedAt) * 1000,
            unit: "ms"
        )
    }
}

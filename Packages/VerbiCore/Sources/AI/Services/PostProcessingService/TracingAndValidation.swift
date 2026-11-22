import Foundation
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

extension PostProcessingService {
    func validateInput(_ transcription: String) throws -> String {
        let trimmedTranscription = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscription.isEmpty else {
            throw PostProcessingError.emptyTranscription
        }

        return trimmedTranscription
    }

    func profile(
        for mode: CaptureMode,
        prefersStructuredPipeline: Bool,
        outputLanguageID: String? = nil
    ) -> RequestProfile {
        switch mode {
        case .meeting:
            RequestProfile(
                name: "meetingProfile",
                timeoutSeconds: Constants.meetingRequestTimeoutSeconds,
                retryCount: Constants.meetingRetryCount,
                useStructuredPipeline: prefersStructuredPipeline,
                useRepair: prefersStructuredPipeline,
                pipeline: prefersStructuredPipeline ? "structured" : "fast",
                outputLanguageID: outputLanguageID
            )
        case .dictation, .assistant:
            RequestProfile(
                name: "dictationProfile",
                timeoutSeconds: Constants.dictationRequestTimeoutSeconds,
                retryCount: 0,
                useStructuredPipeline: prefersStructuredPipeline,
                useRepair: prefersStructuredPipeline,
                pipeline: prefersStructuredPipeline ? "structured" : "fast",
                outputLanguageID: outputLanguageID
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
            outputLanguageID: nil
        )
    }

    func makeTraceContext(
        mode: CaptureMode,
        provider: LLMProvider,
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
        for mode: CaptureMode,
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
        mode: CaptureMode,
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

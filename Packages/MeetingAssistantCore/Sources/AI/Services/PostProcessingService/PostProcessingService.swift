import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

// MARK: - Post-Processing Service

/// Service for post-processing transcriptions using AI.
@MainActor
public final class PostProcessingService: ObservableObject, PostProcessingServiceProtocol {
    public static let shared = PostProcessingService()

    enum Constants {
        /// Maximum tokens for AI response (suitable for long meeting notes).
        static let maxTokens = 4096
        /// Request timeout in seconds (AI responses can be slow for long texts).
        static let meetingRequestTimeoutSeconds: TimeInterval = 120
        /// Dictation budget for the main post-processing request.
        static let dictationRequestTimeoutSeconds: TimeInterval = 25
        /// Dictation budget for timeout fallback fast request.
        static let dictationFallbackTimeoutSeconds: TimeInterval = 8
        /// Anthropic API version header value.
        static let anthropicAPIVersion = "2023-06-01"
        /// Retry count for meeting profile (3 attempts total).
        static let meetingRetryCount = 2
        /// Base delay for exponential backoff (in nanoseconds).
        static let baseRetryDelay: UInt64 = 1_000_000_000 // 1 second
    }

    struct RequestProfile {
        let name: String
        let timeoutSeconds: TimeInterval
        let retryCount: Int
        let useStructuredPipeline: Bool
        let useRepair: Bool
        let pipeline: String
        let useLiveSettings: Bool
        let outputLanguageID: String?
    }

    struct RequestTraceContext {
        let mode: IntelligenceKernelMode
        let provider: AIProvider
        let model: String
        let promptId: String
        let promptTitle: String
        let pipeline: String
    }

    @Published public internal(set) var isProcessing = false
    @Published public internal(set) var lastError: PostProcessingError?

    /// Compatibility-only source for legacy overloads; explicit requests carry all operation values.
    let settings = AppSettingsStore.shared

    let providerHTTPClient = ProviderHTTPClient()

    let summaryResponseParser = CanonicalSummaryResponseParser()
    let summaryPromptComposer = CanonicalSummaryPromptComposer()
    let summaryRepairComposer = CanonicalSummaryRepairComposer()
    let summaryFallbackBuilder = DeterministicSummaryFallbackBuilder()
    let summaryRenderer = CanonicalSummaryRenderer()

    private init() {}

    deinit {
        AppLogger.debug("PostProcessingService deinitialized", category: .transcriptionEngine)
    }
}

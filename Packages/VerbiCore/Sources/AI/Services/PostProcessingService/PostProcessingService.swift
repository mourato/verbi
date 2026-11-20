import Foundation
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

@MainActor
public final class PostProcessingService: ObservableObject, PostProcessingServiceProtocol {
    public static let shared = PostProcessingService()

    enum Constants {
        static let maxTokens = 4096
        static let meetingRequestTimeoutSeconds: TimeInterval = 120
        static let dictationRequestTimeoutSeconds: TimeInterval = 25
        static let dictationFallbackTimeoutSeconds: TimeInterval = 8
        static let anthropicAPIVersion = "2023-06-01"
        static let meetingRetryCount = 2
        static let baseRetryDelay: UInt64 = 1_000_000_000
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
        let mode: CaptureMode
        let provider: LLMProvider
        let model: String
        let promptId: String
        let promptTitle: String
        let pipeline: String
    }

    @Published public internal(set) var isProcessing = false
    @Published public internal(set) var lastError: PostProcessingError?

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

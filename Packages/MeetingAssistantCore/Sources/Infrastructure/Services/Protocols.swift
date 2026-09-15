import Combine
import Foundation
import MeetingAssistantCoreDomain

// MARK: - Audio Recording Protocol

/// Abstract interface for audio recording services.
@MainActor
public protocol AudioRecordingService: ObservableObject {
    var isRecording: Bool { get }
    var isRecordingPublisher: AnyPublisher<Bool, Never> { get } // For Combine observation
    var currentRecordingURL: URL? { get }
    var error: Error? { get }

    /// Start recording to the specified URL.
    func startRecording(to outputURL: URL, retryCount: Int) async throws

    /// Stop recording and return the URL of the created file.
    func stopRecording() async -> URL?

    /// Check if permission is granted.
    func hasPermission() async -> Bool

    /// Request permission from the user.
    func requestPermission() async

    /// Get the detailed permission state.
    func getPermissionState() -> PermissionState

    /// Open system settings for this permission.
    func openSettings()
}

/// Default implementation for retryCount (since it's not always needed)
public extension AudioRecordingService {
    func startRecording(to outputURL: URL) async throws {
        try await startRecording(to: outputURL, retryCount: 0)
    }
}

// MARK: - Transcription Protocol

/// Abstract interface for transcription services.
@MainActor
public protocol TranscriptionService: ObservableObject {
    /// Check service health.
    func healthCheck() async throws -> Bool

    /// Fetch detailed service status.
    func fetchServiceStatus() async throws -> ServiceStatusResponse

    /// Transcribe an audio file.
    func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> TranscriptionResponse

    /// Transcribe a window of mono 16kHz PCM float samples.
    func transcribe(
        samples: [Float]
    ) async throws -> TranscriptionResponse

    /// Executes a file request using the caller's captured provider/model data.
    func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        executionMode: TranscriptionExecutionMode,
        diarizationEnabledOverride: Bool?,
        configuration: DomainTranscriptionRequestConfiguration
    ) async throws -> TranscriptionResponse

    /// Executes an incremental request using the caller's captured provider/model data.
    func transcribe(
        samples: [Float],
        configuration: DomainTranscriptionRequestConfiguration
    ) async throws -> TranscriptionResponse

    func supportsIncrementalTranscription(selection: TranscriptionProviderSelection) -> Bool
}

public extension TranscriptionService {
    func transcribe(
        audioURL _: URL,
        onProgress _: (@Sendable (Double) -> Void)?,
        executionMode _: TranscriptionExecutionMode,
        diarizationEnabledOverride _: Bool?,
        configuration _: DomainTranscriptionRequestConfiguration
    ) throws -> TranscriptionResponse {
        throw TranscriptionError.transcriptionFailed("Explicit transcription configuration is unsupported")
    }

    func transcribe(
        samples _: [Float],
        configuration _: DomainTranscriptionRequestConfiguration
    ) throws -> TranscriptionResponse {
        throw TranscriptionError.transcriptionFailed("Explicit transcription configuration is unsupported")
    }

    func supportsIncrementalTranscription(selection _: TranscriptionProviderSelection) -> Bool {
        false
    }
}

@MainActor
public protocol TranscriptionServiceDiarizationOverride: ObservableObject {
    func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        diarizationEnabledOverride: Bool?
    ) async throws -> TranscriptionResponse
}

@MainActor
public protocol TranscriptionServicePurposeAware: ObservableObject {
    func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        capturePurpose: CapturePurpose
    ) async throws -> TranscriptionResponse
}

@MainActor
public protocol TranscriptionServicePurposeDiarized: ObservableObject {
    func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        diarizationEnabledOverride: Bool?,
        capturePurpose: CapturePurpose
    ) async throws -> TranscriptionResponse
}

@MainActor
public protocol TranscriptionServiceFinalDiarization: ObservableObject {
    func diarize(audioURL: URL) async throws -> [SpeakerTimelineSegment]
    func assignSpeakers(
        to segments: [Transcription.Segment],
        using speakerTimeline: [SpeakerTimelineSegment]
    ) -> [Transcription.Segment]
}

// MARK: - Post-Processing Protocol

/// Configuration frozen by the operation edge before AI execution begins.
public struct PostProcessingRequest: Sendable {
    public let prompt: PostProcessingPrompt?
    public let mode: IntelligenceKernelMode
    public let selection: EnhancementsAISelection?
    public let configuration: AIConfiguration
    public let readinessIssue: String?
    public let outputLanguageID: String?
    public let useStructuredPipeline: Bool
    public let systemPromptOverride: String?

    public init(
        prompt: PostProcessingPrompt?,
        mode: IntelligenceKernelMode,
        selection: EnhancementsAISelection?,
        configuration: AIConfiguration,
        readinessIssue: String? = nil,
        outputLanguageID: String? = nil,
        useStructuredPipeline: Bool,
        systemPromptOverride: String? = nil
    ) {
        self.prompt = prompt
        self.mode = mode
        self.selection = selection
        self.configuration = configuration
        self.readinessIssue = readinessIssue
        self.outputLanguageID = outputLanguageID
        self.useStructuredPipeline = useStructuredPipeline
        self.systemPromptOverride = systemPromptOverride
    }
}

/// Abstract interface for AI post-processing services.
@MainActor
public protocol PostProcessingServiceProtocol: ObservableObject {
    func processTranscription(_ transcription: String, request: PostProcessingRequest) async throws -> String
    func processTranscriptionStructured(_ transcription: String, request: PostProcessingRequest) async throws -> DomainPostProcessingResult

    var isProcessing: Bool { get }
    var lastError: PostProcessingError? { get }

    /// Process a raw transcription text using the selected prompt.
    func processTranscription(_ transcription: String) async throws -> String

    /// Process a raw transcription using a specific prompt.
    func processTranscription(_ transcription: String, with prompt: PostProcessingPrompt) async throws -> String

    /// Process a raw transcription using a specific prompt and a kernel mode-aware configuration.
    func processTranscription(
        _ transcription: String,
        with prompt: PostProcessingPrompt,
        mode: IntelligenceKernelMode,
        systemPromptOverride: String?
    ) async throws -> String

    /// Process a raw transcription using a specific prompt and an explicit enhancements model selection.
    func processTranscription(
        _ transcription: String,
        with prompt: PostProcessingPrompt,
        mode: IntelligenceKernelMode,
        selectionOverride: EnhancementsAISelection,
        systemPromptOverride: String?
    ) async throws -> String

    /// Process transcription using hardened structured summary pipeline.
    func processTranscriptionStructured(_ transcription: String) async throws -> DomainPostProcessingResult

    /// Process transcription using hardened structured summary pipeline and a specific prompt.
    func processTranscriptionStructured(
        _ transcription: String,
        with prompt: PostProcessingPrompt
    ) async throws -> DomainPostProcessingResult

    /// Process transcription using hardened structured summary pipeline and a specific prompt with mode-aware configuration.
    func processTranscriptionStructured(
        _ transcription: String,
        with prompt: PostProcessingPrompt,
        mode: IntelligenceKernelMode
    ) async throws -> DomainPostProcessingResult

    /// Process transcription using hardened structured summary pipeline with an explicit enhancements model selection.
    func processTranscriptionStructured(
        _ transcription: String,
        with prompt: PostProcessingPrompt,
        mode: IntelligenceKernelMode,
        selectionOverride: EnhancementsAISelection
    ) async throws -> DomainPostProcessingResult
}

public extension PostProcessingServiceProtocol {
    func processTranscription(
        _ transcription: String,
        with prompt: PostProcessingPrompt,
        mode _: IntelligenceKernelMode,
        selectionOverride _: EnhancementsAISelection,
        systemPromptOverride _: String?
    ) async throws -> String {
        try await processTranscription(
            transcription,
            with: prompt
        )
    }

    func processTranscription(
        _ transcription: String,
        with prompt: PostProcessingPrompt,
        mode _: IntelligenceKernelMode,
        systemPromptOverride _: String?
    ) async throws -> String {
        try await processTranscription(
            transcription,
            with: prompt
        )
    }

    func processTranscriptionStructured(
        _ transcription: String,
        with prompt: PostProcessingPrompt,
        mode _: IntelligenceKernelMode
    ) async throws -> DomainPostProcessingResult {
        try await processTranscriptionStructured(
            transcription,
            with: prompt
        )
    }

    func processTranscriptionStructured(
        _ transcription: String,
        with prompt: PostProcessingPrompt,
        mode _: IntelligenceKernelMode,
        selectionOverride _: EnhancementsAISelection
    ) async throws -> DomainPostProcessingResult {
        try await processTranscriptionStructured(
            transcription,
            with: prompt
        )
    }
}

// MARK: - Grounded Meeting Q&A Protocol

/// Abstract interface for reusable, mode-aware intelligence Q&A.
@MainActor
public protocol IntelligenceKernelServiceProtocol: ObservableObject {
    var isAnswering: Bool { get }
    var lastError: MeetingQAError? { get }

    /// Ask a single-turn grounded question through the shared intelligence kernel.
    func ask(_ request: IntelligenceKernelQuestionRequest) async throws -> MeetingQAResponse
}

public extension IntelligenceKernelServiceProtocol {
    /// Compatibility helper for existing meeting-only call sites.
    func ask(question: String, transcription: Transcription) async throws -> MeetingQAResponse {
        try await ask(
            IntelligenceKernelQuestionRequest(
                mode: .meeting,
                question: question,
                transcription: transcription
            )
        )
    }
}

/// Backward-compatible alias protocol for grounded meeting Q&A.
@MainActor
public protocol MeetingQAServiceProtocol: IntelligenceKernelServiceProtocol {}

// MARK: - Notification Service Protocol

/// Abstract interface for notification services.
public protocol NotificationServiceProtocol {
    /// Request notification authorization.
    func requestAuthorization()

    /// Show notification for recording started.
    func showRecordingStarted()

    /// Show notification for recording stopped.
    func showRecordingStopped()

    /// Show notification for transcription completed.
    func showTranscriptionCompleted()

    /// Show notification for transcription failed.
    func showTranscriptionFailed()

    /// Send a custom notification.
    func sendNotification(title: String, body: String)
}

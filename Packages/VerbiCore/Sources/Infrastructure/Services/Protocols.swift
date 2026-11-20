import Combine
import Foundation
import VerbiCoreDomain

@MainActor
public protocol AudioRecordingService: ObservableObject {
    var isRecording: Bool { get }
    var isRecordingPublisher: AnyPublisher<Bool, Never> { get }
    var currentRecordingURL: URL? { get }
    var error: Error? { get }

    func startRecording(to outputURL: URL, retryCount: Int) async throws

    func stopRecording() async -> URL?

    func hasPermission() async -> Bool

    func requestPermission() async

    func getPermissionState() -> PermissionState

    func openSettings()
}

public extension AudioRecordingService {
    func startRecording(to outputURL: URL) async throws {
        try await startRecording(to: outputURL, retryCount: 0)
    }
}

@MainActor
public protocol TranscriptionService: ObservableObject {
    func healthCheck() async throws -> Bool

    func fetchServiceStatus() async throws -> ServiceStatusResponse

    func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> TranscriptionResponse

    func transcribe(
        samples: [Float]
    ) async throws -> TranscriptionResponse

    func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        executionMode: CaptureMode,
        diarizationEnabledOverride: Bool?,
        configuration: DomainTranscriptionRequestConfiguration
    ) async throws -> TranscriptionResponse

    func transcribe(
        samples: [Float],
        configuration: DomainTranscriptionRequestConfiguration
    ) async throws -> TranscriptionResponse

    func supportsIncrementalTranscription(selection: TranscriptionProviderSelection) -> Bool

    func supportsIncrementalTranscription(
        selection: TranscriptionProviderSelection,
        mode: CaptureMode
    ) -> Bool
}

public extension TranscriptionService {
    func transcribe(
        audioURL _: URL,
        onProgress _: (@Sendable (Double) -> Void)?,
        executionMode _: CaptureMode,
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

    func supportsIncrementalTranscription(
        selection: TranscriptionProviderSelection,
        mode _: CaptureMode
    ) -> Bool {
        supportsIncrementalTranscription(selection: selection)
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
        to segments: [CaptureArtifact.Segment],
        using speakerTimeline: [SpeakerTimelineSegment]
    ) -> [CaptureArtifact.Segment]
}

public struct PostProcessingRequest: Sendable {
    public let prompt: PostProcessingPrompt?
    public let mode: CaptureMode
    public let selection: EnhancementsAISelection?
    public let configuration: AIConfiguration
    public let readinessIssue: String?
    public let outputLanguageID: String?
    public let useStructuredPipeline: Bool
    public let systemPromptOverride: String?

    public init(
        prompt: PostProcessingPrompt?,
        mode: CaptureMode,
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

@MainActor
public protocol PostProcessingServiceProtocol: ObservableObject {
    func processTranscription(_ transcription: String, request: PostProcessingRequest) async throws -> String
    func processTranscriptionStructured(_ transcription: String, request: PostProcessingRequest) async throws -> DomainPostProcessingResult

    var isProcessing: Bool { get }
    var lastError: PostProcessingError? { get }

    func processTranscription(_ transcription: String) async throws -> String

    func processTranscription(_ transcription: String, with prompt: PostProcessingPrompt) async throws -> String

    func processTranscription(
        _ transcription: String,
        with prompt: PostProcessingPrompt,
        mode: CaptureMode,
        systemPromptOverride: String?
    ) async throws -> String

    func processTranscription(
        _ transcription: String,
        with prompt: PostProcessingPrompt,
        mode: CaptureMode,
        selectionOverride: EnhancementsAISelection,
        systemPromptOverride: String?
    ) async throws -> String

    func processTranscriptionStructured(_ transcription: String) async throws -> DomainPostProcessingResult

    func processTranscriptionStructured(
        _ transcription: String,
        with prompt: PostProcessingPrompt
    ) async throws -> DomainPostProcessingResult

    func processTranscriptionStructured(
        _ transcription: String,
        with prompt: PostProcessingPrompt,
        mode: CaptureMode
    ) async throws -> DomainPostProcessingResult

    func processTranscriptionStructured(
        _ transcription: String,
        with prompt: PostProcessingPrompt,
        mode: CaptureMode,
        selectionOverride: EnhancementsAISelection
    ) async throws -> DomainPostProcessingResult
}

public extension PostProcessingServiceProtocol {
    func processTranscription(
        _ transcription: String,
        with prompt: PostProcessingPrompt,
        mode _: CaptureMode,
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
        mode _: CaptureMode,
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
        mode _: CaptureMode
    ) async throws -> DomainPostProcessingResult {
        try await processTranscriptionStructured(
            transcription,
            with: prompt
        )
    }

    func processTranscriptionStructured(
        _ transcription: String,
        with prompt: PostProcessingPrompt,
        mode _: CaptureMode,
        selectionOverride _: EnhancementsAISelection
    ) async throws -> DomainPostProcessingResult {
        try await processTranscriptionStructured(
            transcription,
            with: prompt
        )
    }
}

@MainActor
public protocol IntelligenceKernelServiceProtocol: ObservableObject {
    var isAnswering: Bool { get }
    var lastError: MeetingQAError? { get }

    func ask(_ request: IntelligenceKernelQuestionRequest) async throws -> MeetingQAResponse
}

public extension IntelligenceKernelServiceProtocol {
    func ask(question: String, transcription: CaptureArtifact) async throws -> MeetingQAResponse {
        try await ask(
            IntelligenceKernelQuestionRequest(
                mode: .meeting,
                question: question,
                transcription: transcription
            )
        )
    }
}

@MainActor
public protocol MeetingQAServiceProtocol: IntelligenceKernelServiceProtocol {}

public protocol NotificationServiceProtocol {
    func requestAuthorization()

    func showRecordingStarted()

    func showRecordingStopped()

    func showTranscriptionCompleted()

    func showTranscriptionFailed()

    func sendNotification(title: String, body: String)
}

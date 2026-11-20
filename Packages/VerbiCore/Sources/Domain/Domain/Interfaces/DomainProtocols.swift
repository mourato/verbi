import Foundation

#if DEBUG
    import VerbiCoreMocking
#endif

#if DEBUG
    @GenerateMock
#endif
public protocol RecordingRepository: Sendable {
    func startRecording(to outputURL: URL, retryCount: Int) async throws

    func stopRecording() async throws -> URL?

    func hasPermission() async -> Bool

    func requestPermission() async

    func getPermissionState() async -> DomainPermissionState

    func openSettings() async
}

#if DEBUG
    @GenerateMock
#endif
public protocol AudioFileRepository: Sendable {
    func saveAudioFile(from sourceURL: URL, to destinationURL: URL) async throws

    func deleteAudioFile(at url: URL) async throws

    func audioFileExists(at url: URL) -> Bool

    func generateAudioFileURL(for meetingId: UUID) -> URL

    func listAudioFiles() async throws -> [URL]
}

#if DEBUG
    @GenerateMock
#endif
public protocol SpeechRecognitionClient: Sendable {
    func healthCheck() async throws -> Bool

    func fetchServiceStatus() async throws -> DomainServiceStatusResponse

    func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> DomainTranscriptionResponse

    func transcribe(
        samples: [Float]
    ) async throws -> DomainTranscriptionResponse

    func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        configuration: DomainTranscriptionRequestConfiguration,
        diarizationEnabledOverride: Bool?,
        capturePurpose: CapturePurpose
    ) async throws -> DomainTranscriptionResponse

    func transcribe(
        samples: [Float],
        configuration: DomainTranscriptionRequestConfiguration
    ) async throws -> DomainTranscriptionResponse
}

public extension SpeechRecognitionClient {
    func transcribe(
        audioURL _: URL,
        onProgress _: (@Sendable (Double) -> Void)?,
        configuration _: DomainTranscriptionRequestConfiguration,
        diarizationEnabledOverride _: Bool?,
        capturePurpose _: CapturePurpose
    ) throws -> DomainTranscriptionResponse {
        throw DomainTranscriptionError.transcriptionFailed("Explicit transcription configuration is unsupported")
    }

    func transcribe(
        samples _: [Float],
        configuration _: DomainTranscriptionRequestConfiguration
    ) throws -> DomainTranscriptionResponse {
        throw DomainTranscriptionError.transcriptionFailed("Explicit transcription configuration is unsupported")
    }
}

public protocol SpeechRecognitionDiarizationOverride: Sendable {
    func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        diarizationEnabledOverride: Bool?
    ) async throws -> DomainTranscriptionResponse
}

public protocol SpeechRecognitionClientPurposeAware: Sendable {
    func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        capturePurpose: CapturePurpose
    ) async throws -> DomainTranscriptionResponse
}

public protocol SpeechRecognitionClientPurposeDiarized: Sendable {
    func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        diarizationEnabledOverride: Bool?,
        capturePurpose: CapturePurpose
    ) async throws -> DomainTranscriptionResponse
}

public struct DomainTranscriptionRequestConfiguration: Codable, Hashable, Sendable {
    public let providerID: String
    public let modelID: String
    public let inputLanguageCode: String?
    public let vocabularyHints: VocabularyProviderHints?

    public init(
        providerID: String,
        modelID: String,
        inputLanguageCode: String?,
        vocabularyHints: VocabularyProviderHints? = nil
    ) {
        self.providerID = providerID
        self.modelID = modelID
        self.inputLanguageCode = inputLanguageCode
        self.vocabularyHints = vocabularyHints
    }
}

@MainActor
public protocol SpeechRecognitionClientFinalDiarization: Sendable {
    func diarize(audioURL: URL) async throws -> [SpeakerTimelineSegment]
    func assignSpeakers(
        to segments: [DomainTranscriptionSegment],
        using speakerTimeline: [SpeakerTimelineSegment]
    ) -> [DomainTranscriptionSegment]
}

#if DEBUG
    @GenerateMock
#endif
public protocol PostProcessingRepository: Sendable {
    func processTranscription(_ transcription: String) async throws -> String

    func processTranscription(
        _ transcription: String,
        mode: CaptureMode
    ) async throws -> String

    func processTranscription(_ transcription: String, with prompt: DomainPostProcessingPrompt) async throws -> String

    func processTranscription(
        _ transcription: String,
        with prompt: DomainPostProcessingPrompt,
        mode: CaptureMode
    ) async throws -> String

    func processTranscriptionStructured(_ transcription: String) async throws -> DomainPostProcessingResult

    func processTranscriptionStructured(
        _ transcription: String,
        mode: CaptureMode
    ) async throws -> DomainPostProcessingResult

    func processTranscriptionStructured(
        _ transcription: String,
        with prompt: DomainPostProcessingPrompt
    ) async throws -> DomainPostProcessingResult

    func processTranscriptionStructured(
        _ transcription: String,
        with prompt: DomainPostProcessingPrompt,
        mode: CaptureMode
    ) async throws -> DomainPostProcessingResult

    func processTranscription(
        _ transcription: String,
        request: DomainPostProcessingRequest
    ) async throws -> String

    func processTranscriptionStructured(
        _ transcription: String,
        request: DomainPostProcessingRequest
    ) async throws -> DomainPostProcessingResult
}

public struct DomainPostProcessingSelection: Codable, Hashable, Sendable {
    public let providerID: String
    public let modelID: String
    public let registrationID: UUID?

    public init(providerID: String, modelID: String, registrationID: UUID?) {
        self.providerID = providerID
        self.modelID = modelID
        self.registrationID = registrationID
    }
}

public struct DomainPostProcessingConfiguration: Codable, Hashable, Sendable {
    public let providerID: String
    public let baseURL: String
    public let modelID: String
    public let readinessIssue: String?
    public let outputLanguageID: String?

    public init(
        providerID: String,
        baseURL: String,
        modelID: String,
        readinessIssue: String? = nil,
        outputLanguageID: String? = nil
    ) {
        self.providerID = providerID
        self.baseURL = baseURL
        self.modelID = modelID
        self.readinessIssue = readinessIssue
        self.outputLanguageID = outputLanguageID
    }

    public static let unconfigured = DomainPostProcessingConfiguration(
        providerID: "openai",
        baseURL: "",
        modelID: "",
        readinessIssue: "enhancements.missing_model"
    )
}

public struct DomainPostProcessingRequest: Sendable {
    public let prompt: DomainPostProcessingPrompt?
    public let mode: CaptureMode
    public let selection: DomainPostProcessingSelection?
    public let configuration: DomainPostProcessingConfiguration
    public let useStructuredPipeline: Bool
    public let systemPromptOverride: String?

    public init(
        prompt: DomainPostProcessingPrompt? = nil,
        mode: CaptureMode,
        selection: DomainPostProcessingSelection? = nil,
        configuration: DomainPostProcessingConfiguration = .unconfigured,
        useStructuredPipeline: Bool,
        systemPromptOverride: String? = nil
    ) {
        self.prompt = prompt
        self.mode = mode
        self.selection = selection
        self.configuration = configuration
        self.useStructuredPipeline = useStructuredPipeline
        self.systemPromptOverride = systemPromptOverride
    }
}

public extension PostProcessingRepository {
    func processTranscription(
        _ transcription: String,
        mode _: CaptureMode
    ) async throws -> String {
        try await processTranscription(transcription)
    }

    func processTranscription(
        _ transcription: String,
        with prompt: DomainPostProcessingPrompt,
        mode _: CaptureMode
    ) async throws -> String {
        try await processTranscription(
            transcription,
            with: prompt
        )
    }

    func processTranscriptionStructured(
        _ transcription: String,
        mode _: CaptureMode
    ) async throws -> DomainPostProcessingResult {
        try await processTranscriptionStructured(transcription)
    }

    func processTranscriptionStructured(
        _ transcription: String,
        with prompt: DomainPostProcessingPrompt,
        mode _: CaptureMode
    ) async throws -> DomainPostProcessingResult {
        try await processTranscriptionStructured(
            transcription,
            with: prompt
        )
    }
}

#if DEBUG
    @GenerateMock
#endif
public protocol MeetingRepository: Sendable {
    func saveMeeting(_ meeting: CaptureSessionEntity) async throws

    func fetchMeeting(by id: UUID) async throws -> CaptureSessionEntity?

    func fetchAllMeetings() async throws -> [CaptureSessionEntity]

    func deleteMeeting(by id: UUID) async throws

    func updateMeeting(_ meeting: CaptureSessionEntity) async throws
}

#if DEBUG
    @GenerateMock
#endif
public protocol TranscriptionStorageRepository: Sendable {
    func saveTranscription(_ transcription: CaptureArtifactEntity) async throws

    func saveModelPerformanceAttempt(_ attempt: ModelPerformanceAttempt) async throws

    func fetchTranscription(by id: UUID) async throws -> CaptureArtifactEntity?

    func fetchTranscriptions(for meetingId: UUID) async throws -> [CaptureArtifactEntity]

    func fetchAllTranscriptions() async throws -> [CaptureArtifactEntity]

    func fetchAllMetadata() async throws -> [DomainTranscriptionMetadata]

    func fetchModelPerformanceAttempts(matching query: ModelPerformanceAttemptQuery) async throws -> [ModelPerformanceAttempt]

    func deleteTranscription(by id: UUID) async throws

    func updateTranscription(_ transcription: CaptureArtifactEntity) async throws
}

public enum DomainPermissionState: Sendable {
    case granted
    case denied
    case notDetermined
    case restricted
}

public struct DomainServiceStatusResponse: Codable, Sendable {
    public let status: String
    public let message: String
    public let timestamp: Date

    public init(status: String, message: String, timestamp: Date = Date()) {
        self.status = status
        self.message = message
        self.timestamp = timestamp
    }
}

public enum DomainPostProcessingError: Error, Sendable {
    case serviceUnavailable
    case invalidPrompt
    case processingFailed(String)
    case networkError(Error)
}

public enum DomainPostProcessingOutputState: String, Codable, Sendable {
    case structured
    case repaired
    case deterministicFallback
}

public struct DomainPostProcessingResult: Sendable {
    public let processedText: String
    public let canonicalSummary: CanonicalSummary
    public let outputState: DomainPostProcessingOutputState

    public init(
        processedText: String,
        canonicalSummary: CanonicalSummary,
        outputState: DomainPostProcessingOutputState
    ) {
        self.processedText = processedText
        self.canonicalSummary = canonicalSummary
        self.outputState = outputState
    }
}

public struct DomainPostProcessingPrompt: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let content: String
    public let isDefault: Bool
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        content: String,
        isDefault: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.isDefault = isDefault
        self.createdAt = createdAt
    }
}

public struct DomainTranscriptionResponse: Codable, Sendable {
    public let text: String
    public let language: String
    public let durationSeconds: Double
    public let model: String
    public let processedAt: String
    public let segments: [DomainTranscriptionSegment]
    public let confidenceScore: Double?

    public init(
        text: String,
        segments: [DomainTranscriptionSegment] = [],
        language: String,
        durationSeconds: Double,
        model: String,
        processedAt: String,
        confidenceScore: Double? = nil
    ) {
        self.text = text
        self.language = language
        self.durationSeconds = durationSeconds
        self.model = model
        self.processedAt = processedAt
        self.segments = segments
        self.confidenceScore = confidenceScore
    }
}

public struct DomainTranscriptionSegment: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let speaker: String
    public let text: String
    public let startTime: Double
    public let endTime: Double

    public init(
        id: UUID = UUID(),
        speaker: String,
        text: String,
        startTime: Double,
        endTime: Double
    ) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
}

public struct DomainTranscriptionMetadata: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let meetingId: UUID
    public let meetingTitle: String?
    public let appName: String
    public let appRawValue: String
    public let capturePurpose: CapturePurpose
    public let appBundleIdentifier: String?
    public let startTime: Date
    public let createdAt: Date
    public let previewText: String
    public let language: String
    public let isPostProcessed: Bool
    public let postProcessingFailureReason: String?
    public let duration: Double
    public let audioFilePath: String?
    public let lifecycleState: TranscriptionLifecycleState
    public let summarySchemaVersion: Int
    public let summaryGroundedInTranscript: Bool
    public let summaryContainsSpeculation: Bool
    public let summaryHumanReviewed: Bool
    public let summaryConfidenceScore: Double
    public let transcriptConfidenceScore: Double
    public let transcriptContainsUncertainty: Bool

    public init(
        id: UUID,
        meetingId: UUID,
        meetingTitle: String? = nil,
        appName: String,
        appRawValue: String,
        capturePurpose: CapturePurpose? = nil,
        appBundleIdentifier: String?,
        startTime: Date,
        createdAt: Date,
        previewText: String,
        language: String,
        isPostProcessed: Bool,
        postProcessingFailureReason: String? = nil,
        duration: Double,
        audioFilePath: String?,
        lifecycleState: TranscriptionLifecycleState = .completed,
        summarySchemaVersion: Int = 0,
        summaryGroundedInTranscript: Bool = false,
        summaryContainsSpeculation: Bool = false,
        summaryHumanReviewed: Bool = false,
        summaryConfidenceScore: Double = 0.0,
        transcriptConfidenceScore: Double = 0.5,
        transcriptContainsUncertainty: Bool = false
    ) {
        self.id = id
        self.meetingId = meetingId
        self.meetingTitle = meetingTitle
        self.appName = appName
        self.appRawValue = appRawValue
        self.capturePurpose = capturePurpose ?? CapturePurpose.defaultValue(for: CaptureOrigin(rawValue: appRawValue) ?? .unknown)
        self.appBundleIdentifier = appBundleIdentifier
        self.startTime = startTime
        self.createdAt = createdAt
        self.previewText = previewText
        self.language = language
        self.isPostProcessed = isPostProcessed
        self.postProcessingFailureReason = postProcessingFailureReason
        self.duration = duration
        self.audioFilePath = audioFilePath
        self.lifecycleState = lifecycleState
        self.summarySchemaVersion = summarySchemaVersion
        self.summaryGroundedInTranscript = summaryGroundedInTranscript
        self.summaryContainsSpeculation = summaryContainsSpeculation
        self.summaryHumanReviewed = summaryHumanReviewed
        self.summaryConfidenceScore = summaryConfidenceScore
        self.transcriptConfidenceScore = transcriptConfidenceScore
        self.transcriptContainsUncertainty = transcriptContainsUncertainty
    }
}

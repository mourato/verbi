// Domain Protocols - Interfaces para infraestrutura seguindo Clean Architecture

import Foundation

#if DEBUG
    import MeetingAssistantCoreMocking
#endif

// MARK: - Recording Domain Protocols

// Protocolo para operações de gravação de áudio
#if DEBUG
    @GenerateMock
#endif
public protocol RecordingRepository: Sendable {
    /// Inicia gravação para URL especificada
    func startRecording(to outputURL: URL, retryCount: Int) async throws

    /// Para gravação e retorna URL do arquivo criado
    func stopRecording() async throws -> URL?

    /// Verifica se permissão está concedida
    func hasPermission() async -> Bool

    /// Solicita permissão do usuário
    func requestPermission() async

    /// Obtém estado detalhado da permissão
    func getPermissionState() async -> DomainPermissionState

    /// Abre configurações do sistema para esta permissão
    func openSettings() async
}

// Protocolo para operações de arquivo de áudio
#if DEBUG
    @GenerateMock
#endif
public protocol AudioFileRepository: Sendable {
    /// Salva arquivo de áudio
    func saveAudioFile(from sourceURL: URL, to destinationURL: URL) async throws

    /// Remove arquivo de áudio
    func deleteAudioFile(at url: URL) async throws

    /// Verifica se arquivo existe
    func audioFileExists(at url: URL) -> Bool

    /// Obtém URL para novo arquivo de áudio
    func generateAudioFileURL(for meetingId: UUID) -> URL

    /// Lista arquivos de áudio
    func listAudioFiles() async throws -> [URL]
}

// MARK: - Transcription Domain Protocols

// Protocolo para operações de transcrição
#if DEBUG
    @GenerateMock
#endif
public protocol TranscriptionRepository: Sendable {
    /// Verifica saúde do serviço
    func healthCheck() async throws -> Bool

    /// Busca status detalhado do serviço
    func fetchServiceStatus() async throws -> DomainServiceStatusResponse

    /// Transcreve arquivo de áudio
    func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> DomainTranscriptionResponse

    /// Transcribe a window of mono 16kHz PCM float samples.
    func transcribe(
        samples: [Float]
    ) async throws -> DomainTranscriptionResponse

    /// Transcribes an audio file using one captured request configuration.
    func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        configuration: DomainTranscriptionRequestConfiguration,
        diarizationEnabledOverride: Bool?,
        capturePurpose: CapturePurpose
    ) async throws -> DomainTranscriptionResponse

    /// Transcribes a sample window using one captured request configuration.
    func transcribe(
        samples: [Float],
        configuration: DomainTranscriptionRequestConfiguration
    ) async throws -> DomainTranscriptionResponse
}

public extension TranscriptionRepository {
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

public protocol TranscriptionRepositoryDiarizationOverride: Sendable {
    func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        diarizationEnabledOverride: Bool?
    ) async throws -> DomainTranscriptionResponse
}

public protocol TranscriptionRepositoryPurposeAware: Sendable {
    func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        capturePurpose: CapturePurpose
    ) async throws -> DomainTranscriptionResponse
}

public protocol TranscriptionRepositoryPurposeDiarized: Sendable {
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
    /// Explicit provider vocabulary projections. Never read from AppSettingsStore in adapters.
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
public protocol TranscriptionRepositoryFinalDiarization: Sendable {
    func diarize(audioURL: URL) async throws -> [SpeakerTimelineSegment]
    func assignSpeakers(
        to segments: [DomainTranscriptionSegment],
        using speakerTimeline: [SpeakerTimelineSegment]
    ) -> [DomainTranscriptionSegment]
}

// Protocolo para operações de pós-processamento
#if DEBUG
    @GenerateMock
#endif
public protocol PostProcessingRepository: Sendable {
    /// Processa texto de transcrição usando prompt selecionado
    func processTranscription(_ transcription: String) async throws -> String

    /// Processa texto de transcrição usando prompt selecionado e modo do kernel.
    func processTranscription(
        _ transcription: String,
        mode: IntelligenceKernelMode
    ) async throws -> String

    /// Processa texto de transcrição usando prompt específico
    func processTranscription(_ transcription: String, with prompt: DomainPostProcessingPrompt) async throws -> String

    /// Processa texto de transcrição usando prompt específico e modo do kernel.
    func processTranscription(
        _ transcription: String,
        with prompt: DomainPostProcessingPrompt,
        mode: IntelligenceKernelMode
    ) async throws -> String

    /// Process transcription with canonical structured summary contract.
    func processTranscriptionStructured(_ transcription: String) async throws -> DomainPostProcessingResult

    /// Process transcription with canonical structured summary contract and kernel mode.
    func processTranscriptionStructured(
        _ transcription: String,
        mode: IntelligenceKernelMode
    ) async throws -> DomainPostProcessingResult

    /// Process transcription with canonical structured summary contract using a specific prompt.
    func processTranscriptionStructured(
        _ transcription: String,
        with prompt: DomainPostProcessingPrompt
    ) async throws -> DomainPostProcessingResult

    /// Process transcription with canonical structured summary contract using a specific prompt and kernel mode.
    func processTranscriptionStructured(
        _ transcription: String,
        with prompt: DomainPostProcessingPrompt,
        mode: IntelligenceKernelMode
    ) async throws -> DomainPostProcessingResult

    /// Canonical operation-edge request for fast post-processing.
    func processTranscription(
        _ transcription: String,
        request: DomainPostProcessingRequest
    ) async throws -> String

    /// Canonical operation-edge request for structured post-processing.
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

/// Immutable operation-edge snapshot for post-processing.
public struct DomainPostProcessingRequest: Sendable {
    public let prompt: DomainPostProcessingPrompt?
    public let mode: IntelligenceKernelMode
    public let selection: DomainPostProcessingSelection?
    public let configuration: DomainPostProcessingConfiguration
    public let useStructuredPipeline: Bool
    public let systemPromptOverride: String?

    public init(
        prompt: DomainPostProcessingPrompt? = nil,
        mode: IntelligenceKernelMode,
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
        mode _: IntelligenceKernelMode
    ) async throws -> String {
        try await processTranscription(transcription)
    }

    func processTranscription(
        _ transcription: String,
        with prompt: DomainPostProcessingPrompt,
        mode _: IntelligenceKernelMode
    ) async throws -> String {
        try await processTranscription(
            transcription,
            with: prompt
        )
    }

    func processTranscriptionStructured(
        _ transcription: String,
        mode _: IntelligenceKernelMode
    ) async throws -> DomainPostProcessingResult {
        try await processTranscriptionStructured(transcription)
    }

    func processTranscriptionStructured(
        _ transcription: String,
        with prompt: DomainPostProcessingPrompt,
        mode _: IntelligenceKernelMode
    ) async throws -> DomainPostProcessingResult {
        try await processTranscriptionStructured(
            transcription,
            with: prompt
        )
    }
}

// MARK: - Storage Domain Protocols

// Protocolo para operações de armazenamento de reuniões
#if DEBUG
    @GenerateMock
#endif
public protocol MeetingRepository: Sendable {
    /// Salva reunião
    func saveMeeting(_ meeting: MeetingEntity) async throws

    /// Busca reunião por ID
    func fetchMeeting(by id: UUID) async throws -> MeetingEntity?

    /// Lista todas as reuniões
    func fetchAllMeetings() async throws -> [MeetingEntity]

    /// Remove reunião
    func deleteMeeting(by id: UUID) async throws

    /// Atualiza reunião
    func updateMeeting(_ meeting: MeetingEntity) async throws
}

// Protocolo para operações de armazenamento de transcrições
#if DEBUG
    @GenerateMock
#endif
public protocol TranscriptionStorageRepository: Sendable {
    /// Salva transcrição
    func saveTranscription(_ transcription: TranscriptionEntity) async throws

    /// Salva tentativa imutável de performance de modelo
    func saveModelPerformanceAttempt(_ attempt: ModelPerformanceAttempt) async throws

    /// Busca transcrição por ID
    func fetchTranscription(by id: UUID) async throws -> TranscriptionEntity?

    /// Lista transcrições para reunião
    func fetchTranscriptions(for meetingId: UUID) async throws -> [TranscriptionEntity]

    /// Lista todas as transcrições (carregamento completo)
    func fetchAllTranscriptions() async throws -> [TranscriptionEntity]

    /// Lista metadados de todas as transcrições (carregamento leve)
    func fetchAllMetadata() async throws -> [DomainTranscriptionMetadata]

    /// Lista tentativas de performance dos modelos (carregamento leve)
    func fetchModelPerformanceAttempts(matching query: ModelPerformanceAttemptQuery) async throws -> [ModelPerformanceAttempt]

    /// Remove transcrição
    func deleteTranscription(by id: UUID) async throws

    /// Atualiza transcrição
    func updateTranscription(_ transcription: TranscriptionEntity) async throws
}

// MARK: - Supporting Types

/// Estados de permissão do domínio
public enum DomainPermissionState: Sendable {
    case granted
    case denied
    case notDetermined
    case restricted
}

/// Resposta de status do serviço do domínio
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

/// Erro de pós-processamento do domínio
public enum DomainPostProcessingError: Error, Sendable {
    case serviceUnavailable
    case invalidPrompt
    case processingFailed(String)
    case networkError(Error)
}

/// Indicates how the canonical summary output was produced.
public enum DomainPostProcessingOutputState: String, Codable, Sendable {
    case structured
    case repaired
    case deterministicFallback
}

/// Structured output for hardened post-processing.
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

/// Prompt de pós-processamento do domínio
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

/// Resposta de transcrição do domínio
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

/// Segmento de transcrição do domínio
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

/// Metadados leve de uma transcrição para listagem eficiente
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
        self.capturePurpose = capturePurpose ?? CapturePurpose.defaultValue(for: DomainMeetingApp(rawValue: appRawValue) ?? .unknown)
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

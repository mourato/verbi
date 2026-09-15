// TranscriptionEntity - Domain Entity pura sem dependências de UI/frameworks

import Foundation

/// Representa uma transcrição completada.
public struct TranscriptionEntity: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let meeting: MeetingEntity
    public let capturePurpose: CapturePurpose

    /// Context items used during post-processing.
    public let contextItems: [TranscriptionContextItem]

    /// Segmentos da transcrição com identificação de speaker.
    public let segments: [Segment]

    /// Texto primário para exibição (processado se disponível, caso contrário raw).
    public let text: String

    /// Transcrição original do modelo ASR.
    public let rawText: String

    /// Conteúdo processado de pós-processamento AI (nil se não processado).
    public var processedContent: String?

    /// Canonical and versioned summary payload (nil when unavailable).
    public var canonicalSummary: CanonicalSummary?

    /// Transcript quality profile used by downstream intelligence stages.
    public var qualityProfile: TranscriptionQualityProfile?

    /// ID do prompt usado para pós-processamento (nil se não processado).
    public var postProcessingPromptId: UUID?

    /// Título do prompt usado para pós-processamento (nil se não processado).
    public var postProcessingPromptTitle: String?

    /// System prompt text actually sent to the provider.
    public var postProcessingRequestSystemPrompt: String?

    /// User prompt text actually sent to the provider.
    public var postProcessingRequestUserPrompt: String?

    public let language: String
    public let createdAt: Date
    public let modelName: String

    // New Metadata Fields
    public let inputSource: String?
    public let transcriptionDuration: Double
    public let postProcessingDuration: Double
    public let postProcessingModel: String?
    public let meetingType: String?
    public let lifecycleState: TranscriptionLifecycleState
    public var meetingConversationState: MeetingConversationState?
    public var postProcessingFailureReason: String?
    public var postProcessingOutputState: DomainPostProcessingOutputState?
    public var transcriptionFailureReason: String?
    public var executionProvenance: ExecutionProvenance?

    /// Inicializador completo com suporte a pós-processamento.
    /// Configuração para inicialização flexível de TranscriptionEntity.
    public struct Configuration: Sendable {
        public var id: UUID = .init()
        public var contextItems: [TranscriptionContextItem] = []
        public var segments: [Segment] = []
        public var text: String
        public var rawText: String
        public var processedContent: String?
        public var canonicalSummary: CanonicalSummary?
        public var qualityProfile: TranscriptionQualityProfile?
        public var postProcessingPromptId: UUID?
        public var postProcessingPromptTitle: String?
        public var postProcessingRequestSystemPrompt: String?
        public var postProcessingRequestUserPrompt: String?
        public var language: String = "pt"
        public var createdAt: Date = .init()
        public var modelName: String = "parakeet-tdt-0.6b-v3"
        public var inputSource: String?
        public var transcriptionDuration: Double = 0
        public var postProcessingDuration: Double = 0
        public var postProcessingModel: String?
        public var meetingType: String?
        public var lifecycleState: TranscriptionLifecycleState = .completed
        public var meetingConversationState: MeetingConversationState?
        public var postProcessingFailureReason: String?
        public var postProcessingOutputState: DomainPostProcessingOutputState?
        public var transcriptionFailureReason: String?
        public var executionProvenance: ExecutionProvenance?

        public init(
            text: String,
            rawText: String? = nil,
            segments: [Segment] = [],
            language: String = "pt"
        ) {
            self.text = text
            self.rawText = rawText ?? text
            self.segments = segments
            self.language = language
        }
    }

    /// Inicializador principal usando Configuration para reduzir lista de argumentos.
    public init(meeting: MeetingEntity, config: Configuration) {
        id = config.id
        self.meeting = meeting
        capturePurpose = meeting.capturePurpose
        contextItems = config.contextItems
        segments = config.segments
        text = config.text
        rawText = config.rawText
        processedContent = config.processedContent
        canonicalSummary = config.canonicalSummary
        qualityProfile = config.qualityProfile
        postProcessingPromptId = config.postProcessingPromptId
        postProcessingPromptTitle = config.postProcessingPromptTitle
        postProcessingRequestSystemPrompt = config.postProcessingRequestSystemPrompt
        postProcessingRequestUserPrompt = config.postProcessingRequestUserPrompt
        language = config.language
        createdAt = config.createdAt
        modelName = config.modelName
        inputSource = config.inputSource
        transcriptionDuration = config.transcriptionDuration
        postProcessingDuration = config.postProcessingDuration
        postProcessingModel = config.postProcessingModel
        meetingType = config.meetingType
        lifecycleState = config.lifecycleState
        meetingConversationState = config.meetingConversationState
        postProcessingFailureReason = config.postProcessingFailureReason
        postProcessingOutputState = config.postProcessingOutputState
        transcriptionFailureReason = config.transcriptionFailureReason
        executionProvenance = config.executionProvenance
    }

    /// Inicializador depreciado mantido para compatibilidade temporária (será removido).
    @available(*, deprecated, message: "Use init(meeting:config:) instead")
    public init(
        id: UUID = UUID(),
        meeting: MeetingEntity,
        segments: [Segment] = [],
        text: String,
        rawText: String,
        processedContent: String? = nil,
        canonicalSummary: CanonicalSummary? = nil,
        postProcessingPromptId: UUID? = nil,
        postProcessingPromptTitle: String? = nil,
        language: String = "pt",
        createdAt: Date = Date(),
        modelName: String = "parakeet-tdt-0.6b-v3"
    ) {
        var config = Configuration(text: text, rawText: rawText, segments: segments, language: language)
        config.id = id
        config.processedContent = processedContent
        config.canonicalSummary = canonicalSummary
        config.qualityProfile = nil
        config.postProcessingPromptId = postProcessingPromptId
        config.postProcessingPromptTitle = postProcessingPromptTitle
        config.createdAt = createdAt
        config.modelName = modelName

        self.init(meeting: meeting, config: config)
    }

    /// Inicializador de conveniência para compatibilidade retroativa (sem pós-processamento).
    @available(*, deprecated, message: "Use init(meeting:config:) instead")
    public init(
        id: UUID = UUID(),
        meeting: MeetingEntity,
        text: String,
        language: String = "pt",
        createdAt: Date = Date(),
        modelName: String = "parakeet-tdt-0.6b-v3"
    ) {
        var config = Configuration(text: text, rawText: text, language: language)
        config.id = id
        config.createdAt = createdAt
        config.modelName = modelName

        self.init(meeting: meeting, config: config)
    }

    /// Se esta transcrição foi pós-processada.
    public var isPostProcessed: Bool {
        processedContent != nil
    }

    /// Contagem de palavras da transcrição.
    public var wordCount: Int {
        text.split(separator: " ").count
    }

    /// Prévia do texto da transcrição (primeiros 100 chars).
    public var preview: String {
        if text.count <= 100 {
            return text
        }
        return String(text.prefix(100)) + "..."
    }

    /// Prévia curta para lista de exibição (primeiros 80 chars).
    public var truncatedPreview: String {
        if text.count <= 80 {
            return text
        }
        return String(text.prefix(80)) + "..."
    }

    /// Um segmento da transcrição associado a um speaker.
    public struct Segment: Identifiable, Codable, Hashable, Sendable {
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

    /// String padrão para speaker desconhecido.
    public static let unknownSpeaker = "Desconhecido"
}

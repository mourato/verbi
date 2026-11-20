import Foundation

public struct CaptureArtifactEntity: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let meeting: CaptureSessionEntity
    public let capturePurpose: CapturePurpose

    public let contextItems: [TranscriptionContextItem]

    public let segments: [Segment]

    public let text: String

    public let rawText: String

    public var processedContent: String?

    public var canonicalSummary: CanonicalSummary?

    public var qualityProfile: TranscriptionQualityProfile?

    public var postProcessingPromptId: UUID?

    public var postProcessingPromptTitle: String?

    public var postProcessingRequestSystemPrompt: String?

    public var postProcessingRequestUserPrompt: String?

    public let language: String
    public let createdAt: Date
    public let modelName: String

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

    public init(meeting: CaptureSessionEntity, config: Configuration) {
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

    @available(*, deprecated, message: "Use init(meeting:config:) instead")
    public init(
        id: UUID = UUID(),
        meeting: CaptureSessionEntity,
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

    @available(*, deprecated, message: "Use init(meeting:config:) instead")
    public init(
        id: UUID = UUID(),
        meeting: CaptureSessionEntity,
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

    public var isPostProcessed: Bool {
        processedContent != nil
    }

    public var wordCount: Int {
        text.split(separator: " ").count
    }

    public var preview: String {
        if text.count <= 100 {
            return text
        }
        return String(text.prefix(100)) + "..."
    }

    public var truncatedPreview: String {
        if text.count <= 80 {
            return text
        }
        return String(text.prefix(80)) + "..."
    }

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

    public static let unknownSpeaker = "Desconhecido"
}

@available(*, deprecated, renamed: "CaptureArtifactEntity")
public typealias TranscriptionEntity = CaptureArtifactEntity

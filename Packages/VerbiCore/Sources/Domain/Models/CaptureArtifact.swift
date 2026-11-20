import Foundation

public struct CaptureArtifact: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let meeting: CaptureSession
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

    public init(
        id: UUID = UUID(),
        meeting: CaptureSession,
        contextItems: [TranscriptionContextItem] = [],
        segments: [Segment] = [],
        text: String,
        rawText: String,
        processedContent: String? = nil,
        canonicalSummary: CanonicalSummary? = nil,
        qualityProfile: TranscriptionQualityProfile? = nil,
        postProcessingPromptId: UUID? = nil,
        postProcessingPromptTitle: String? = nil,
        postProcessingRequestSystemPrompt: String? = nil,
        postProcessingRequestUserPrompt: String? = nil,
        language: String = "pt",
        createdAt: Date = Date(),
        modelName: String = "parakeet-tdt-0.6b-v3",
        inputSource: String? = nil,
        transcriptionDuration: Double = 0,
        postProcessingDuration: Double = 0,
        postProcessingModel: String? = nil,
        meetingType: String? = nil,
        lifecycleState: TranscriptionLifecycleState = .completed,
        meetingConversationState: MeetingConversationState? = nil,
        postProcessingFailureReason: String? = nil,
        postProcessingOutputState: DomainPostProcessingOutputState? = nil,
        transcriptionFailureReason: String? = nil,
        executionProvenance: ExecutionProvenance? = nil
    ) {
        self.id = id
        self.meeting = meeting
        capturePurpose = meeting.capturePurpose
        self.contextItems = contextItems
        self.segments = segments
        self.text = text
        self.rawText = rawText
        self.processedContent = processedContent
        self.canonicalSummary = canonicalSummary
        self.qualityProfile = qualityProfile
        self.postProcessingPromptId = postProcessingPromptId
        self.postProcessingPromptTitle = postProcessingPromptTitle
        self.postProcessingRequestSystemPrompt = postProcessingRequestSystemPrompt
        self.postProcessingRequestUserPrompt = postProcessingRequestUserPrompt
        self.language = language
        self.createdAt = createdAt
        self.modelName = modelName
        self.inputSource = inputSource
        self.transcriptionDuration = transcriptionDuration
        self.postProcessingDuration = postProcessingDuration
        self.postProcessingModel = postProcessingModel
        self.meetingType = meetingType
        self.lifecycleState = lifecycleState
        self.meetingConversationState = meetingConversationState
        self.postProcessingFailureReason = postProcessingFailureReason
        self.postProcessingOutputState = postProcessingOutputState
        self.transcriptionFailureReason = transcriptionFailureReason
        self.executionProvenance = executionProvenance
    }

    public init(
        id: UUID = UUID(),
        meeting: CaptureSession,
        text: String,
        language: String = "pt",
        createdAt: Date = Date(),
        modelName: String = "parakeet-tdt-0.6b-v3"
    ) {
        self.init(
            id: id,
            meeting: meeting,
            contextItems: [],
            segments: [],
            text: text,
            rawText: text,
            processedContent: nil,
            canonicalSummary: nil,
            qualityProfile: nil,
            postProcessingPromptId: nil,
            postProcessingPromptTitle: nil,
            language: language,
            createdAt: createdAt,
            modelName: modelName
        )
    }

    public var isPostProcessed: Bool {
        processedContent != nil
    }

    public var audioURL: URL? {
        guard let path = meeting.audioFilePath else { return nil }
        return URL(fileURLWithPath: path)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter
    }()

    public var formattedDate: String {
        Self.dateFormatter.string(from: createdAt)
    }

    public var formattedDuration: String {
        meeting.formattedDuration
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

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    public var formattedTime: String {
        Self.timeFormatter.string(from: createdAt)
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

@available(*, deprecated, renamed: "CaptureArtifact")
public typealias Transcription = CaptureArtifact

public struct TranscriptionContextItem: Identifiable, Codable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable {
        case activeApp
        case activeTabURL
        case windowTitle
        case accessibilityText
        case clipboard
        case windowOCR
        case focusedText
        case selectedTextAtStart
        case calendarEvent
        case meetingNotes
    }

    public let id: UUID
    public let source: Source
    public let text: String

    public init(id: UUID = UUID(), source: Source, text: String) {
        self.id = id
        self.source = source
        self.text = text
    }
}

public struct SpeakerTimelineSegment: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let speaker: String
    public let startTime: Double
    public let endTime: Double

    public init(
        id: UUID = UUID(),
        speaker: String,
        startTime: Double,
        endTime: Double
    ) {
        self.id = id
        self.speaker = speaker
        self.startTime = startTime
        self.endTime = endTime
    }
}

public struct TranscriptionResponse: Codable, Sendable {
    public let text: String
    public let language: String
    public let durationSeconds: Double
    public let model: String
    public let processedAt: String
    public let segments: [CaptureArtifact.Segment]
    public let confidenceScore: Double?

    enum CodingKeys: String, CodingKey {
        case text
        case segments
        case language
        case durationSeconds = "duration_seconds"
        case model
        case processedAt = "processed_at"
        case confidenceScore = "confidence_score"
    }

    public init(
        text: String,
        segments: [CaptureArtifact.Segment] = [],
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

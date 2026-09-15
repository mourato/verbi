import Foundation

/// Represents a completed transcription.
public struct Transcription: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let meeting: Meeting
    public let capturePurpose: CapturePurpose

    /// Context items used during post-processing.
    public let contextItems: [TranscriptionContextItem]

    /// Segments of the transcription with speaker identification.
    public let segments: [Segment]

    /// Primary text for display (processed if available, otherwise raw).
    public let text: String

    /// Original transcription from the ASR model.
    public let rawText: String

    /// Processed content from AI post-processing (nil if not processed).
    public var processedContent: String?

    /// Canonical and versioned summary payload (nil when unavailable).
    public var canonicalSummary: CanonicalSummary?

    /// Transcript quality profile used by downstream intelligence stages.
    public var qualityProfile: TranscriptionQualityProfile?

    /// ID of the prompt used for post-processing (nil if not processed).
    public var postProcessingPromptId: UUID?

    /// Title of the prompt used for post-processing (nil if not processed).
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

    /// Reason why post-processing was skipped or failed (nil if successful or not attempted).
    public var postProcessingFailureReason: String?

    /// How structured post-processing produced the canonical summary (nil when not structured).
    public var postProcessingOutputState: DomainPostProcessingOutputState?

    /// Reason why ASR / transcription itself failed (nil when transcription succeeded).
    public var transcriptionFailureReason: String?

    /// Immutable request metadata used by default historical retry.
    public var executionProvenance: ExecutionProvenance?

    /// Full initializer with post-processing support.
    public init(
        id: UUID = UUID(),
        meeting: Meeting,
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

    /// Convenience initializer for backward compatibility (no post-processing).
    public init(
        id: UUID = UUID(),
        meeting: Meeting,
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

    /// Whether this transcription was post-processed.
    public var isPostProcessed: Bool {
        processedContent != nil
    }

    /// URL to the audio recording file (if available).
    public var audioURL: URL? {
        guard let path = meeting.audioFilePath else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Whether meeting-only conversation features should be enabled.
    public var supportsMeetingConversation: Bool {
        meeting.supportsMeetingConversation
    }

    /// Cached formatter for transcription dates.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter
    }()

    /// Formatted date string for display.
    public var formattedDate: String {
        Self.dateFormatter.string(from: createdAt)
    }

    /// Duration from meeting data.
    public var formattedDuration: String {
        meeting.formattedDuration
    }

    /// Word count of transcription.
    public var wordCount: Int {
        text.split(separator: " ").count
    }

    /// Preview of transcription text (first 100 chars).
    public var preview: String {
        if text.count <= 100 {
            return text
        }
        return String(text.prefix(100)) + "..."
    }

    /// Short preview for list display (first 80 chars).
    public var truncatedPreview: String {
        if text.count <= 80 {
            return text
        }
        return String(text.prefix(80)) + "..."
    }

    /// Cached time formatter for transcription times.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// Formatted time string for display.
    public var formattedTime: String {
        Self.timeFormatter.string(from: createdAt)
    }

    /// A segment of the transcription associated with a speaker.
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

    /// Default string for unknown speaker.
    public static let unknownSpeaker = "Desconhecido"
}

/// Context item sent to the post-processing provider.
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

/// Speaker timeline segment produced by diarization.
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

/// Response from transcription API.
public struct TranscriptionResponse: Codable, Sendable {
    public let text: String
    public let language: String
    public let durationSeconds: Double
    public let model: String
    public let processedAt: String
    public let segments: [Transcription.Segment]
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
        segments: [Transcription.Segment] = [],
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

import Foundation

/// Lightweight representation of a transcription for list display and filtering.
public struct TranscriptionMetadata: Identifiable, Codable, Hashable, Sendable {
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
    public let wordCount: Int
    public let language: String
    public let isPostProcessed: Bool
    public let postProcessingFailureReason: String?
    public let duration: TimeInterval
    public let audioFilePath: String?
    public let inputSource: String?
    public let lifecycleState: TranscriptionLifecycleState
    public let summarySchemaVersion: Int
    public let summaryGroundedInTranscript: Bool
    public let summaryContainsSpeculation: Bool
    public let summaryHumanReviewed: Bool
    public let summaryConfidenceScore: Double
    public let transcriptConfidenceScore: Double
    public let transcriptContainsUncertainty: Bool

    public var meetingApp: MeetingApp {
        MeetingApp(rawValue: appRawValue) ?? .unknown
    }

    /// Whether meeting-only conversation features should be enabled.
    public var supportsMeetingConversation: Bool {
        capturePurpose == .meeting
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case meetingId
        case meetingTitle
        case appName
        case appRawValue
        case capturePurpose
        case appBundleIdentifier
        case startTime
        case createdAt
        case previewText
        case wordCount
        case language
        case isPostProcessed
        case postProcessingFailureReason
        case duration
        case audioFilePath
        case inputSource
        case lifecycleState
        case summarySchemaVersion
        case summaryGroundedInTranscript
        case summaryContainsSpeculation
        case summaryHumanReviewed
        case summaryConfidenceScore
        case transcriptConfidenceScore
        case transcriptContainsUncertainty
    }

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
        wordCount: Int,
        language: String,
        isPostProcessed: Bool,
        postProcessingFailureReason: String? = nil,
        duration: TimeInterval,
        audioFilePath: String?,
        inputSource: String?,
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
        let resolvedMeetingApp = MeetingApp(rawValue: appRawValue) ?? .unknown
        self.capturePurpose = capturePurpose ?? CapturePurpose.defaultValue(for: resolvedMeetingApp)
        self.appBundleIdentifier = appBundleIdentifier
        self.startTime = startTime
        self.createdAt = createdAt
        self.previewText = previewText
        self.wordCount = wordCount
        self.language = language
        self.isPostProcessed = isPostProcessed
        self.postProcessingFailureReason = postProcessingFailureReason
        self.duration = duration
        self.audioFilePath = audioFilePath
        self.inputSource = inputSource
        self.lifecycleState = lifecycleState
        self.summarySchemaVersion = summarySchemaVersion
        self.summaryGroundedInTranscript = summaryGroundedInTranscript
        self.summaryContainsSpeculation = summaryContainsSpeculation
        self.summaryHumanReviewed = summaryHumanReviewed
        self.summaryConfidenceScore = summaryConfidenceScore
        self.transcriptConfidenceScore = transcriptConfidenceScore
        self.transcriptContainsUncertainty = transcriptContainsUncertainty
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let id = try container.decode(UUID.self, forKey: .id)
        let meetingId = try container.decode(UUID.self, forKey: .meetingId)
        let meetingTitle = try container.decodeIfPresent(String.self, forKey: .meetingTitle)
        let appName = try container.decode(String.self, forKey: .appName)
        let appRawValue = try container.decode(String.self, forKey: .appRawValue)
        let capturePurpose = try container.decodeIfPresent(CapturePurpose.self, forKey: .capturePurpose)
        let appBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .appBundleIdentifier)
        let startTime = try container.decode(Date.self, forKey: .startTime)
        let createdAt = try container.decode(Date.self, forKey: .createdAt)
        let previewText = try container.decode(String.self, forKey: .previewText)
        let wordCount = try container.decodeIfPresent(Int.self, forKey: .wordCount) ?? 0
        let language = try container.decode(String.self, forKey: .language)
        let isPostProcessed = try container.decode(Bool.self, forKey: .isPostProcessed)
        let postProcessingFailureReason = try container.decodeIfPresent(String.self, forKey: .postProcessingFailureReason)
        let duration = try container.decode(TimeInterval.self, forKey: .duration)
        let audioFilePath = try container.decodeIfPresent(String.self, forKey: .audioFilePath)
        let inputSource = try container.decodeIfPresent(String.self, forKey: .inputSource)
        let lifecycleState = try container.decodeIfPresent(TranscriptionLifecycleState.self, forKey: .lifecycleState) ?? .completed
        let summarySchemaVersion = try container.decodeIfPresent(Int.self, forKey: .summarySchemaVersion) ?? 0
        let summaryGroundedInTranscript = try container.decodeIfPresent(Bool.self, forKey: .summaryGroundedInTranscript) ?? false
        let summaryContainsSpeculation = try container.decodeIfPresent(Bool.self, forKey: .summaryContainsSpeculation) ?? false
        let summaryHumanReviewed = try container.decodeIfPresent(Bool.self, forKey: .summaryHumanReviewed) ?? false
        let summaryConfidenceScore = try container.decodeIfPresent(Double.self, forKey: .summaryConfidenceScore) ?? 0.0
        let transcriptConfidenceScore = try container.decodeIfPresent(Double.self, forKey: .transcriptConfidenceScore) ?? 0.5
        let transcriptContainsUncertainty = try container.decodeIfPresent(Bool.self, forKey: .transcriptContainsUncertainty) ?? false

        self.init(
            id: id,
            meetingId: meetingId,
            meetingTitle: meetingTitle,
            appName: appName,
            appRawValue: appRawValue,
            capturePurpose: capturePurpose,
            appBundleIdentifier: appBundleIdentifier,
            startTime: startTime,
            createdAt: createdAt,
            previewText: previewText,
            wordCount: wordCount,
            language: language,
            isPostProcessed: isPostProcessed,
            postProcessingFailureReason: postProcessingFailureReason,
            duration: duration,
            audioFilePath: audioFilePath,
            inputSource: inputSource,
            lifecycleState: lifecycleState,
            summarySchemaVersion: summarySchemaVersion,
            summaryGroundedInTranscript: summaryGroundedInTranscript,
            summaryContainsSpeculation: summaryContainsSpeculation,
            summaryHumanReviewed: summaryHumanReviewed,
            summaryConfidenceScore: summaryConfidenceScore,
            transcriptConfidenceScore: transcriptConfidenceScore,
            transcriptContainsUncertainty: transcriptContainsUncertainty
        )
    }
}

/// Query options for loading transcription metadata directly from persistence.
public struct TranscriptionMetadataQuery: Hashable, Sendable {
    public let sourceFilter: RecordingSourceFilter
    public let dateFilter: DateFilter
    public let searchText: String
    public let appRawValue: String?
    public let includeNonVisibleLifecycleStates: Bool
    public let limit: Int?
    public let sortNewestFirst: Bool

    public init(
        sourceFilter: RecordingSourceFilter = .all,
        dateFilter: DateFilter = .allEntries,
        searchText: String = "",
        appRawValue: String? = nil,
        includeNonVisibleLifecycleStates: Bool = false,
        limit: Int? = nil,
        sortNewestFirst: Bool = true
    ) {
        self.sourceFilter = sourceFilter
        self.dateFilter = dateFilter
        self.searchText = searchText
        self.appRawValue = appRawValue
        self.includeNonVisibleLifecycleStates = includeNonVisibleLifecycleStates
        self.limit = limit
        self.sortNewestFirst = sortNewestFirst
    }
}

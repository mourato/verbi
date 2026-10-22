import Foundation
import VerbiCoreCommon

/// Represents the nature of the meeting to guide AI summarization strategies.
public enum SummaryStrategy: String, CaseIterable, Codable, Sendable {
    /// The system will analyze the transcript to determine the best fit strategy
    case autodetect

    /// A balanced summary suitable for most standard business meetings
    case general

    /// Optimized for daily status updates, progress, and blockers
    case standup

    /// Focuses on design decisions, visual feedback, and critiques
    case designReview = "design_review"

    /// Focused on career development, personal feedback, and alignment
    case oneOnOne = "one_on_one"

    /// Optimized for technical talks, demos, or slides; focusing on key takeaways
    case presentation

    /// Focused on task allocation, timelines, and roadmap discussions
    case planning
}

public extension SummaryStrategy {
    var displayName: String {
        switch self {
        case .autodetect: "meeting.type.autodetect".localized
        case .general: "meeting.type.general".localized
        case .standup: "meeting.type.standup".localized
        case .designReview: "meeting.type.design_review".localized
        case .oneOnOne: "meeting.type.one_on_one".localized
        case .presentation: "meeting.type.presentation".localized
        case .planning: "meeting.type.planning".localized
        }
    }

    var iconName: String {
        switch self {
        case .autodetect: "sparkles"
        case .general: "bubble.left.and.bubble.right"
        case .standup: "figure.stand"
        case .designReview: "paintbrush"
        case .oneOnOne: "person.2"
        case .presentation: "tv"
        case .planning: "map"
        }
    }
}

/// Compatibility name for the pre-phase-3 summary strategy type.
@available(*, deprecated, renamed: "SummaryStrategy")
public typealias MeetingType = SummaryStrategy

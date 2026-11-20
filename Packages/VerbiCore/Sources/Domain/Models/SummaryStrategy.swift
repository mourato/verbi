import Foundation
import VerbiCoreCommon

public enum SummaryStrategy: String, CaseIterable, Codable, Sendable {
    case autodetect

    case general

    case standup

    case designReview = "design_review"

    case oneOnOne = "one_on_one"

    case presentation

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

@available(*, deprecated, renamed: "SummaryStrategy")
public typealias MeetingType = SummaryStrategy

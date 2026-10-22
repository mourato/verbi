import Foundation
import MeetingAssistantCoreCommon

/// Filter for transcription source type.
public enum CapturePurposeFilter: String, CaseIterable, Sendable {
    case all
    case dictations
    case meetings

    /// Display name for the filter option.
    public var displayName: String {
        switch self {
        case .all:
            "filter.source.all".localized
        case .dictations:
            "filter.source.dictations".localized
        case .meetings:
            "filter.source.meetings".localized
        }
    }
}

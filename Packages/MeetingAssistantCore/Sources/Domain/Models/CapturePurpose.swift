import Foundation
import MeetingAssistantCoreCommon

public enum CapturePurpose: String, CaseIterable, Codable, Sendable {
    case dictation
    case meeting

    public var supportsMeetingConversation: Bool {
        self == .meeting
    }

    public var displayName: String {
        switch self {
        case .dictation:
            "metrics.performance.filter.dictation".localized
        case .meeting:
            "metrics.performance.filter.meeting".localized
        }
    }

    public var intelligenceKernelMode: IntelligenceKernelMode {
        self == .dictation ? .dictation : .meeting
    }

    public static func defaultValue(for app: MeetingApp) -> CapturePurpose {
        switch app {
        case .unknown:
            .dictation
        case .importedFile:
            .dictation
        default:
            .meeting
        }
    }

    public static func defaultValue(for app: DomainMeetingApp) -> CapturePurpose {
        switch app {
        case .unknown:
            .dictation
        case .importedFile:
            .dictation
        default:
            .meeting
        }
    }
}

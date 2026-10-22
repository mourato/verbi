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

    public var captureMode: CaptureMode {
        self == .dictation ? .dictation : .meeting
    }

    /// Compatibility accessor for clients that still use the old kernel name.
    @available(*, deprecated, renamed: "captureMode")
    public var intelligenceKernelMode: CaptureMode {
        captureMode
    }

    /// Compatibility accessor for clients that still use the old transcription name.
    @available(*, deprecated, renamed: "captureMode")
    public var transcriptionExecutionMode: CaptureMode {
        captureMode
    }

    public static func defaultValue(for app: CaptureOrigin) -> CapturePurpose {
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

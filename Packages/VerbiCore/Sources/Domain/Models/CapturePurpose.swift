import Foundation
import VerbiCoreCommon

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

    @available(*, deprecated, renamed: "captureMode")
    public var intelligenceKernelMode: CaptureMode {
        captureMode
    }

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

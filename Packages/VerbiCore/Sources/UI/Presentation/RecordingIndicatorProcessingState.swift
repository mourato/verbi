import Combine
import Foundation

public enum RecordingIndicatorProcessingStep: String, Sendable, Equatable, CaseIterable {
    case preparingAudio
    case transcribingAudio
    case transcribingFailed
    case detectingMeetingType
    case postProcessing
    case postProcessingFailed
    case finalizingResult
    case transcribingCommand
    case capturingContext
    case interpretingCommand
    case dispatchingResult

    public var localizedTitleKey: String {
        switch self {
        case .preparingAudio:
            "recording_indicator.processing.step.preparing_audio"
        case .transcribingAudio:
            "recording_indicator.processing.step.transcribing_audio"
        case .transcribingFailed:
            "recording_indicator.processing.step.transcribing_failed"
        case .postProcessingFailed:
            "recording_indicator.processing.step.post_processing_failed"
        case .detectingMeetingType:
            "recording_indicator.processing.step.detecting_meeting_type"
        case .postProcessing:
            "recording_indicator.processing.step.post_processing"
        case .finalizingResult:
            "recording_indicator.processing.step.finalizing_result"
        case .transcribingCommand:
            "recording_indicator.processing.step.transcribing_command"
        case .capturingContext:
            "recording_indicator.processing.step.capturing_context"
        case .interpretingCommand:
            "recording_indicator.processing.step.interpreting_command"
        case .dispatchingResult:
            "recording_indicator.processing.step.dispatching_result"
        }
    }
}

public struct RecordingIndicatorProcessingSnapshot: Sendable, Equatable {
    public let step: RecordingIndicatorProcessingStep
    public let progressPercent: Double?

    public init(step: RecordingIndicatorProcessingStep, progressPercent: Double? = nil) {
        self.step = step
        self.progressPercent = progressPercent.map { min(max($0, 0), 100) }
    }
}

@MainActor
public final class RecordingIndicatorProcessingStateStore: ObservableObject {
    public static let shared = RecordingIndicatorProcessingStateStore()

    @Published public private(set) var currentSnapshot: RecordingIndicatorProcessingSnapshot?

    public init(currentSnapshot: RecordingIndicatorProcessingSnapshot? = nil) {
        self.currentSnapshot = currentSnapshot
    }

    public func update(snapshot: RecordingIndicatorProcessingSnapshot) {
        currentSnapshot = snapshot
    }

    public func reset() {
        currentSnapshot = nil
    }
}

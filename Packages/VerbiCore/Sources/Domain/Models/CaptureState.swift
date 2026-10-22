import Foundation

/// Represents the current state of a meeting in the recording/processing pipeline.
public enum CaptureState: Equatable, Sendable, Codable, Hashable {
    /// CaptureSession has not started
    case idle

    /// Currently recording audio
    case recording

    /// Recording is paused
    case paused

    /// Processing audio (transcription, summarization, etc.)
    case processing(Stage)

    /// CaptureSession processing is complete and artifacts are generated
    case completed

    /// An error occurred during the lifecycle
    case failed(String)

    public enum Stage: String, Equatable, Sendable, Codable, Hashable {
        case transcribing
        case summarizing
        case generatingOutput
    }
}

/// Compatibility name for the pre-phase-3 capture lifecycle type.
@available(*, deprecated, renamed: "CaptureState")
public typealias MeetingState = CaptureState

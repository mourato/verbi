import Foundation

public enum CaptureState: Equatable, Sendable, Codable, Hashable {
    case idle

    case recording

    case paused

    case processing(Stage)

    case completed

    case failed(String)

    public enum Stage: String, Equatable, Sendable, Codable, Hashable {
        case transcribing
        case summarizing
        case generatingOutput
    }
}

@available(*, deprecated, renamed: "CaptureState")
public typealias MeetingState = CaptureState

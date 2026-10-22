import Foundation

/// Persistence lifecycle for a transcription record.
public enum TranscriptionLifecycleState: String, Codable, Hashable, Sendable {
    case partial
    case finalizing
    case completed
    case failed

    public var isVisibleInHistory: Bool {
        switch self {
        case .completed, .failed:
            true
        case .partial, .finalizing:
            false
        }
    }
}

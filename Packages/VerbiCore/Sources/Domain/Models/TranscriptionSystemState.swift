import Foundation

/// Represents the current state of the transcription service.
public enum ServiceState: String, Codable, Equatable, Sendable {
    case unknown
    case connecting
    case connected
    case disconnected
    case error
}

/// Represents the model loading state.
public enum ModelState: String, Codable, Equatable, Sendable {
    case unloaded
    case downloading
    case loading
    case loaded
    case error
}

/// Represents the transcription processing phase.
public enum TranscriptionPhase: String, Codable, Equatable, Sendable {
    case idle
    case preparing
    case processing
    case postProcessing = "post_processing"
    case completed
    case failed
}

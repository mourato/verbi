import Foundation

public enum ServiceState: String, Codable, Equatable, Sendable {
    case unknown
    case connecting
    case connected
    case disconnected
    case error
}

public enum ModelState: String, Codable, Equatable, Sendable {
    case unloaded
    case downloading
    case loading
    case loaded
    case error
}

public enum TranscriptionPhase: String, Codable, Equatable, Sendable {
    case idle
    case preparing
    case processing
    case postProcessing = "post_processing"
    case completed
    case failed
}

import Foundation

/// Response from the `/status` endpoint with detailed service information.
public struct ServiceStatusResponse: Codable, Sendable {
    public let status: String
    public let modelState: String
    public let modelLoaded: Bool
    public let device: String
    public let modelName: String
    public let uptimeSeconds: Double
    public let lastTranscriptionTime: String?
    public let totalTranscriptions: Int
    public let totalAudioProcessedSeconds: Double

    enum CodingKeys: String, CodingKey {
        case status
        case modelState = "model_state"
        case modelLoaded = "model_loaded"
        case device
        case modelName = "model_name"
        case uptimeSeconds = "uptime_seconds"
        case lastTranscriptionTime = "last_transcription_time"
        case totalTranscriptions = "total_transcriptions"
        case totalAudioProcessedSeconds = "total_audio_processed_seconds"
    }

    public init(
        status: String,
        modelState: String,
        modelLoaded: Bool,
        device: String,
        modelName: String,
        uptimeSeconds: Double,
        lastTranscriptionTime: String?,
        totalTranscriptions: Int,
        totalAudioProcessedSeconds: Double
    ) {
        self.status = status
        self.modelState = modelState
        self.modelLoaded = modelLoaded
        self.device = device
        self.modelName = modelName
        self.uptimeSeconds = uptimeSeconds
        self.lastTranscriptionTime = lastTranscriptionTime
        self.totalTranscriptions = totalTranscriptions
        self.totalAudioProcessedSeconds = totalAudioProcessedSeconds
    }

    public var modelStateEnum: ModelState {
        switch modelState {
        case "loaded": .loaded
        case "loading": .loading
        case "downloading": .downloading
        case "error": .error
        default: .unloaded
        }
    }
}

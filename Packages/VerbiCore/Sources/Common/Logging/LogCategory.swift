import Foundation

/// Application log categories for grouping logs in Console.app
public enum LogCategory: String, CaseIterable {
    case recordingManager = "RecordingManager"
    case assistant = "Assistant"
    case transcriptionEngine = "TranscriptionEngine"
    case databaseManager = "DatabaseManager"
    case networkService = "NetworkService"
    case uiController = "UIController"

    /// Default fallback
    case general = "General"

    // Monitoring & Observability
    case audio = "Audio"
    case transcription = "Transcription" // Replaces transcriptionEngine over time
    case storage = "Storage" // General storage category
    case network = "Network"
    case performance = "Performance"
    case health = "Health"
    case security = "Security"
}

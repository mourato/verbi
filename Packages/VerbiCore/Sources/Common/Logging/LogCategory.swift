import Foundation

public enum LogCategory: String, CaseIterable {
    case recordingManager = "RecordingManager"
    case assistant = "Assistant"
    case transcriptionEngine = "TranscriptionEngine"
    case databaseManager = "DatabaseManager"
    case networkService = "NetworkService"
    case uiController = "UIController"

    case general = "General"

    case audio = "Audio"
    case transcription = "Transcription"
    case storage = "Storage"
    case network = "Network"
    case performance = "Performance"
    case health = "Health"
    case security = "Security"
}

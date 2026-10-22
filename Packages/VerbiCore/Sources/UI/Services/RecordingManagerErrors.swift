import Foundation

// MARK: - Errors

public enum RecordingManagerError: LocalizedError {
    case noOutputPath
    case mergeFailed(Error)
    case noInputFiles

    public var errorDescription: String? {
        switch self {
        case .noOutputPath:
            "No output path specified for merged audio"
        case let .mergeFailed(error):
            "Audio merge failed: \(error.localizedDescription)"
        case .noInputFiles:
            "No audio files recorded"
        }
    }
}

public enum AudioImportError: LocalizedError {
    case fileNotFound
    case unsupportedFormat

    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            "Audio file not found"
        case .unsupportedFormat:
            "Unsupported audio format. Supported formats: m4a, mp3, wav"
        }
    }
}

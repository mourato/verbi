import Foundation
import VerbiCoreCommon

public enum TranscriptionError: LocalizedError {
    case serviceUnavailable
    case warmupFailed
    case invalidResponse
    case invalidURL(String)
    case transcriptionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .serviceUnavailable:
            "error.transcription.service_unavailable".localized
        case .warmupFailed:
            "error.transcription.warmup_failed".localized
        case .invalidResponse:
            "error.transcription.invalid_response".localized
        case let .invalidURL(urlString):
            "error.transcription.invalid_url".localized(with: urlString)
        case let .transcriptionFailed(message):
            "error.transcription.failed".localized(with: message)
        }
    }
}

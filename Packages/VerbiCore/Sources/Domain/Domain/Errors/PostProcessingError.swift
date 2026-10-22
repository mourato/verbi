import Foundation
import VerbiCoreCommon

public enum PostProcessingError: LocalizedError {
    case noPromptSelected
    case noAPIConfigured
    case invalidURL
    case requestFailed(Error)
    case invalidResponse
    case apiError(String)
    case emptyTranscription
    case configurationNotReady(reason: String, modeName: String)

    public var errorDescription: String? {
        switch self {
        case .noPromptSelected:
            "error.post_processing.no_prompt_selected".localized
        case .noAPIConfigured:
            "error.post_processing.no_api_configured".localized
        case .invalidURL:
            "error.post_processing.invalid_url".localized
        case let .requestFailed(error):
            "error.post_processing.request_failed".localized(with: error.localizedDescription)
        case .invalidResponse:
            "error.post_processing.invalid_response".localized
        case let .apiError(message):
            "error.post_processing.api_error".localized(with: message)
        case .emptyTranscription:
            "error.post_processing.empty_transcription".localized
        case let .configurationNotReady(reason, modeName):
            "error.post_processing.configuration_not_ready".localized(with: Self.localizedReason(for: reason), modeName)
        }
    }

    private static func localizedReason(for reasonCode: String) -> String {
        switch reasonCode {
        case "enhancements.missing_api_key":
            "error.post_processing.configuration_not_ready.missing_api_key".localized
        case "enhancements.missing_model":
            "error.post_processing.configuration_not_ready.missing_model".localized
        case "enhancements.invalid_base_url":
            "error.post_processing.configuration_not_ready.invalid_base_url".localized
        default:
            reasonCode
        }
    }
}

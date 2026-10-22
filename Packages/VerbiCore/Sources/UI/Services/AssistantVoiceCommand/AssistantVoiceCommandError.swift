import Foundation

public enum AssistantVoiceCommandError: LocalizedError {
    case microphonePermissionRequired
    case accessibilityPermissionRequired
    case noSelectionFound
    case emptyCommand
    case failedToStartRecording
    case failedToStopRecording
    case recordingInProgress
    case assistantDisabled
    case processingFailed
    case integrationDisabled
    case raycastIntegrationDisabled
    case raycastDeeplinkInvalid
    case raycastOpenFailed

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionRequired:
            "assistant.error.microphone_permission".localized
        case .accessibilityPermissionRequired:
            "assistant.error.accessibility_permission".localized
        case .noSelectionFound:
            "assistant.error.no_selection".localized
        case .emptyCommand:
            "assistant.error.empty_command".localized
        case .failedToStartRecording:
            "assistant.error.start_failed".localized
        case .failedToStopRecording:
            "assistant.error.stop_failed".localized
        case .recordingInProgress:
            "assistant.error.recording_in_progress".localized
        case .assistantDisabled:
            "assistant.error.disabled".localized
        case .processingFailed:
            "assistant.error.processing_failed".localized
        case .integrationDisabled:
            "assistant.error.integration_disabled".localized
        case .raycastIntegrationDisabled:
            "assistant.error.raycast_integration_disabled".localized
        case .raycastDeeplinkInvalid:
            "assistant.error.raycast_deeplink_invalid".localized
        case .raycastOpenFailed:
            "assistant.error.raycast_open_failed".localized
        }
    }
}

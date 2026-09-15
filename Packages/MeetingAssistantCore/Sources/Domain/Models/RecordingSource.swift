import Foundation
import MeetingAssistantCoreCommon

/// Defines the source of audio to be recorded.
public enum RecordingSource: String, CaseIterable, Sendable {
    case microphone
    case system
    case all

    /// Display name for the source option.
    public var displayName: String {
        switch self {
        case .microphone:
            "recording.source.microphone".localized
        case .system:
            "recording.source.system".localized
        case .all:
            "recording.source.all".localized
        }
    }

    public var requiredPermissionTypes: [PermissionType] {
        switch self {
        case .microphone:
            [.microphone]
        case .system:
            [.screenRecording]
        case .all:
            [.microphone, .screenRecording]
        }
    }

    public var requiresMicrophonePermission: Bool {
        requiredPermissionTypes.contains(.microphone)
    }

    public var requiresScreenRecordingPermission: Bool {
        requiredPermissionTypes.contains(.screenRecording)
    }

    public func requiredPermissionsGranted(
        microphone: PermissionState,
        screenRecording: PermissionState
    ) -> Bool {
        requiredPermissionsGranted(
            microphone: microphone.isAuthorized,
            screenRecording: screenRecording.isAuthorized
        )
    }

    public func requiredPermissionsGranted(
        microphone: Bool,
        screenRecording: Bool
    ) -> Bool {
        switch self {
        case .microphone:
            microphone
        case .system:
            screenRecording
        case .all:
            microphone && screenRecording
        }
    }
}

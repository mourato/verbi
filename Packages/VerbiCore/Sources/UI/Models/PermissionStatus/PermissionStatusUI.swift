import SwiftUI
import VerbiCoreAI
import VerbiCoreAudio
import VerbiCoreCommon
import VerbiCoreData
import VerbiCoreDomain
import VerbiCoreInfrastructure

public enum PermissionAction {
    case request
    case openSettings
    case none
}

@MainActor
public extension PermissionInfo {
    var actionType: PermissionAction {
        switch state {
        case .notDetermined:
            .request
        case .denied, .restricted:
            // Accessibility starts as "denied" until we check the system setting.
            // Keeping this behavior preserves the previous UX.
            type == .accessibility ? .request : .openSettings
        case .granted:
            .none
        }
    }

    var statusColor: Color {
        switch state {
        case .granted:
            AppDesignSystem.Colors.success
        case .denied:
            AppDesignSystem.Colors.error
        case .notDetermined:
            AppDesignSystem.Colors.warning
        case .restricted:
            AppDesignSystem.Colors.neutral
        }
    }

    var iconBackgroundColor: Color {
        statusColor.opacity(0.1)
    }

    var iconForegroundColor: Color {
        switch state {
        case .notDetermined:
            AppDesignSystem.Colors.accent
        default:
            statusColor
        }
    }
}

/// Observable container for all application permissions.
@MainActor
public final class PermissionStatusManager: ObservableObject {
    @Published public private(set) var microphonePermission: PermissionInfo
    @Published public private(set) var screenRecordingPermission: PermissionInfo
    @Published public private(set) var accessibilityPermission: PermissionInfo

    public var allPermissionsGranted: Bool {
        microphonePermission.state.isAuthorized
            && screenRecordingPermission.state.isAuthorized
            && accessibilityPermission.state.isAuthorized
    }

    public var grantedCount: Int {
        var count = 0
        if microphonePermission.state.isAuthorized {
            count += 1
        }
        if screenRecordingPermission.state.isAuthorized {
            count += 1
        }
        if accessibilityPermission.state.isAuthorized {
            count += 1
        }
        return count
    }

    public let totalPermissions = 3

    public init() {
        microphonePermission = PermissionInfo(type: .microphone)
        screenRecordingPermission = PermissionInfo(type: .screenRecording)
        accessibilityPermission = PermissionInfo(type: .accessibility)
    }

    public func updateMicrophoneState(_ state: PermissionState) {
        microphonePermission.updateState(state)
    }

    public func updateScreenRecordingState(_ state: PermissionState) {
        screenRecordingPermission.updateState(state)
    }

    public func updateAccessibilityState(_ state: PermissionState) {
        accessibilityPermission.updateState(state)
    }
}

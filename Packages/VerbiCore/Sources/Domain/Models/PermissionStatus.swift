import Foundation
import VerbiCoreCommon

public enum PermissionConstants {
    public enum Icons {
        public static let shieldCheckered = "shield.checkered"
        public static let exclamationMark = "exclamationmark"
        public static let exclamationMarkTriangle = "exclamationmark.triangle"
    }
}

public enum PermissionState: String, Sendable {
    case granted
    case denied
    case notDetermined
    case restricted

    public var displayName: String {
        switch self {
        case .granted:
            "permission.state.granted".localized
        case .denied:
            "permission.state.denied".localized
        case .notDetermined:
            "permission.state.not_determined".localized
        case .restricted:
            "permission.state.restricted".localized
        }
    }

    public var iconName: String {
        switch self {
        case .granted:
            "checkmark.circle.fill"
        case .denied:
            "xmark.circle.fill"
        case .notDetermined:
            "questionmark.circle.fill"
        case .restricted:
            "lock.circle.fill"
        }
    }

    public var isAuthorized: Bool {
        self == .granted
    }
}

public enum PermissionType: String, CaseIterable, Sendable {
    case microphone
    case screenRecording
    case accessibility

    public var displayName: String {
        switch self {
        case .microphone:
            "permission.type.microphone".localized
        case .screenRecording:
            "permission.type.screen_recording".localized
        case .accessibility:
            "permission.type.accessibility".localized
        }
    }

    public var iconName: String {
        switch self {
        case .microphone:
            "mic.fill"
        case .screenRecording:
            "tv.fill"
        case .accessibility:
            "accessibility"
        }
    }

    public var permissionDescription: String {
        switch self {
        case .microphone:
            "permission.type.microphone.desc".localized
        case .screenRecording:
            "permission.type.screen_recording.desc".localized
        case .accessibility:
            "permission.type.accessibility.desc".localized
        }
    }
}

public struct PermissionInfo: Sendable {
    public let type: PermissionType
    public var state: PermissionState
    public var lastChecked: Date?

    public init(
        type: PermissionType,
        state: PermissionState = .notDetermined,
        lastChecked: Date? = nil
    ) {
        self.type = type
        self.state = state
        self.lastChecked = lastChecked
    }

    public mutating func updateState(_ newState: PermissionState) {
        state = newState
        lastChecked = Date()
    }
}

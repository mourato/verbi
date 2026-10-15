import Foundation

/// Signals representing app-level microphone attribution and call activity for meeting detection.
public struct MeetingDetectionSignals: Equatable, Sendable {
    public enum Attribution: String, Equatable, Sendable, CaseIterable {
        case resolved
        case unattributed
        case unavailable
    }

    public let microphoneOwnerBundleIdentifier: String?
    public let microphoneOwnerDisplayName: String?
    public let attribution: Attribution
    public let activeCallBundleIdentifiers: [String]

    public init(
        microphoneOwnerBundleIdentifier: String? = nil,
        microphoneOwnerDisplayName: String? = nil,
        attribution: Attribution = .unavailable,
        activeCallBundleIdentifiers: [String] = []
    ) {
        self.microphoneOwnerBundleIdentifier = microphoneOwnerBundleIdentifier
        self.microphoneOwnerDisplayName = microphoneOwnerDisplayName
        self.attribution = attribution
        self.activeCallBundleIdentifiers = activeCallBundleIdentifiers
    }

    public var isResolved: Bool {
        attribution == .resolved
    }

    public var isUnattributed: Bool {
        attribution == .unattributed
    }

    public var isUnavailable: Bool {
        attribution == .unavailable
    }
}

import Foundation

/// Paired bundled sound cues played when recording starts and stops.
public enum SoundFeedbackCue: String, CaseIterable, Codable, Sendable, Identifiable {
    case light
    case creamy
    case thocky
    case petal

    public static let defaultCue: Self = .light
    public static let defaultVolume: Float = 1.0

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .light:
            "Light"
        case .creamy:
            "Creamy"
        case .thocky:
            "Thocky"
        case .petal:
            "Petal"
        }
    }

    /// Resource filename (without `.m4a` extension) played when recording starts.
    public var startResourceName: String {
        "\(rawValue)_start"
    }

    /// Resource filename (without `.m4a` extension) played when recording stops.
    public var stopResourceName: String {
        "\(rawValue)_stop"
    }

    /// Clamps user volume preferences to the valid playback range `[0, 1]`.
    public static func clampedVolume(_ volume: Float) -> Float {
        min(max(volume, 0), 1)
    }
}

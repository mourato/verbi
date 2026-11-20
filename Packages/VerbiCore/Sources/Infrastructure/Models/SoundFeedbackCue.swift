import Foundation
import VerbiCoreCommon

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
            "settings.general.sound_feedback.cue.light".localized
        case .creamy:
            "settings.general.sound_feedback.cue.creamy".localized
        case .thocky:
            "settings.general.sound_feedback.cue.thocky".localized
        case .petal:
            "settings.general.sound_feedback.cue.petal".localized
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

    /// Preserves an upgrading user's muted intent when both legacy start and stop sounds were `.none`.
    public static func resolveMigratedEnabledState(
        defaults: UserDefaults = .standard,
        enabledKey: String,
        cueKey: String,
        legacyStartKey: String,
        legacyStopKey: String
    ) -> Bool {
        let storedEnabled = defaults.bool(forKey: enabledKey)
        guard storedEnabled, defaults.string(forKey: cueKey) == nil else {
            return storedEnabled
        }
        let legacyStartIsNone = defaults.string(forKey: legacyStartKey) == SoundFeedbackSound.none.rawValue
        let legacyStopIsNone = defaults.string(forKey: legacyStopKey) == SoundFeedbackSound.none.rawValue
        if legacyStartIsNone, legacyStopIsNone {
            defaults.set(false, forKey: enabledKey)
            return false
        }
        return true
    }
}

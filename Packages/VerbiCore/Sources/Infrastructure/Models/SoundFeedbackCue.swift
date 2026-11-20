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

    /// Result of resolving persisted and legacy sound feedback settings.
    public struct MigratedSettings: Equatable, Sendable {
        public let enabled: Bool
        public let cue: SoundFeedbackCue
    }

    /// Maps a legacy macOS system sound selection to its closest bundled cue pair.
    public static func migratedCue(from legacySound: SoundFeedbackSound) -> Self? {
        switch legacySound {
        case .none:
            nil
        case .glass, .ping, .tink, .morse, .sosumi:
            .light
        case .purr, .submarine, .blow, .hero:
            .creamy
        case .pop, .bottle, .funk, .basso:
            .thocky
        case .frog:
            .petal
        }
    }

    /// One-time migration from legacy start/stop system sounds to the paired bundled cue model.
    ///
    /// Persists the resolved `soundFeedbackCue` key as a durable marker so subsequent launches
    /// never re-run the migration or undo an explicit user re-enable.
    public static func resolveMigratedSettings(
        defaults: UserDefaults = .standard,
        enabledKey: String,
        cueKey: String,
        legacyStartKey: String,
        legacyStopKey: String
    ) -> MigratedSettings {
        let storedEnabled = defaults.bool(forKey: enabledKey)
        if let rawCue = defaults.string(forKey: cueKey), let cue = Self(rawValue: rawCue) {
            return MigratedSettings(enabled: storedEnabled, cue: cue)
        }

        let rawLegacyStart = defaults.string(forKey: legacyStartKey)
        let rawLegacyStop = defaults.string(forKey: legacyStopKey)
        guard rawLegacyStart != nil || rawLegacyStop != nil else {
            return MigratedSettings(enabled: storedEnabled, cue: .defaultCue)
        }

        let legacyStart = rawLegacyStart.flatMap { SoundFeedbackSound(rawValue: $0) }
        let legacyStop = rawLegacyStop.flatMap { SoundFeedbackSound(rawValue: $0) }

        if legacyStart == SoundFeedbackSound.none, legacyStop == SoundFeedbackSound.none {
            defaults.set(Self.defaultCue.rawValue, forKey: cueKey)
            if storedEnabled {
                defaults.set(false, forKey: enabledKey)
            }
            return MigratedSettings(enabled: false, cue: .defaultCue)
        }

        let mappedCue = legacyStart.flatMap(migratedCue(from:))
            ?? legacyStop.flatMap(migratedCue(from:))
            ?? .defaultCue
        defaults.set(mappedCue.rawValue, forKey: cueKey)
        return MigratedSettings(enabled: storedEnabled, cue: mappedCue)
    }
}

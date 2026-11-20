import Foundation
import VerbiCoreCommon

/// Paired bundled sound cues played when recording starts and stops.
public enum SoundFeedbackCue: String, CaseIterable, Codable, Sendable, Identifiable {
    case light
    case creamy
    case thocky
    case petal

    /// Result of resolving persisted and legacy sound feedback settings.
    public struct MigratedSettings: Equatable, Sendable {
        public let enabled: Bool
        public let cue: SoundFeedbackCue
    }

    /// UserDefaults keys used for sound feedback persistence and legacy migration.
    public struct StorageKeys: Sendable {
        public let enabled: String
        public let cue: String
        public let legacyStart: String
        public let legacyStop: String

        public init(enabled: String, cue: String, legacyStart: String, legacyStop: String) {
            self.enabled = enabled
            self.cue = cue
            self.legacyStart = legacyStart
            self.legacyStop = legacyStop
        }
    }

    public static let defaultCue: Self = .light
    public static let defaultVolume: Float = 1.0

    private static let legacyCueMap: [SoundFeedbackSound: Self] = [
        .glass: .light, .ping: .light, .tink: .light, .morse: .light, .sosumi: .light,
        .purr: .creamy, .submarine: .creamy, .blow: .creamy, .hero: .creamy,
        .pop: .thocky, .bottle: .thocky, .funk: .thocky, .basso: .thocky,
        .frog: .petal
    ]

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

    /// Maps a legacy macOS system sound selection to its closest bundled cue pair.
    public static func migratedCue(from legacySound: SoundFeedbackSound) -> Self? {
        legacyCueMap[legacySound]
    }

    /// One-time migration from legacy start/stop system sounds to the paired bundled cue model.
    ///
    /// Persists the resolved `soundFeedbackCue` key as a durable marker so subsequent launches
    /// never re-run the migration or undo an explicit user re-enable.
    public static func resolveMigratedSettings(
        keys: StorageKeys,
        defaults: UserDefaults = .standard
    ) -> MigratedSettings {
        let storedEnabled = defaults.bool(forKey: keys.enabled)
        if let savedCue = defaults.string(forKey: keys.cue).flatMap(Self.init(rawValue:)) {
            return MigratedSettings(enabled: storedEnabled, cue: savedCue)
        }

        let legacyStart = defaults.string(forKey: keys.legacyStart).flatMap(SoundFeedbackSound.init(rawValue:))
        let legacyStop = defaults.string(forKey: keys.legacyStop).flatMap(SoundFeedbackSound.init(rawValue:))
        guard legacyStart != nil || legacyStop != nil else {
            return MigratedSettings(enabled: storedEnabled, cue: .defaultCue)
        }

        return applyLegacyMigration(
            LegacySelection(storedEnabled: storedEnabled, start: legacyStart, stop: legacyStop),
            keys: keys,
            defaults: defaults
        )
    }

    private struct LegacySelection {
        let storedEnabled: Bool
        let start: SoundFeedbackSound?
        let stop: SoundFeedbackSound?
    }

    private static func applyLegacyMigration(
        _ legacy: LegacySelection,
        keys: StorageKeys,
        defaults: UserDefaults
    ) -> MigratedSettings {
        if legacy.start == SoundFeedbackSound.none, legacy.stop == SoundFeedbackSound.none {
            defaults.set(defaultCue.rawValue, forKey: keys.cue)
            defaults.set(false, forKey: keys.enabled)
            return MigratedSettings(enabled: false, cue: .defaultCue)
        }

        let mappedCue = legacy.start.flatMap(migratedCue(from:))
            ?? legacy.stop.flatMap(migratedCue(from:))
            ?? .defaultCue
        defaults.set(mappedCue.rawValue, forKey: keys.cue)
        return MigratedSettings(enabled: legacy.storedEnabled, cue: mappedCue)
    }
}

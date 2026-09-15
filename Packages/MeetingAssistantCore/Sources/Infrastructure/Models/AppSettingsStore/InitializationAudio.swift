import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain

extension AppSettingsStore {
    /// Struct for audio and language settings to avoid large tuple.
    struct AudioAndLanguageSettingsValues {
        let selectedLanguage: AppLanguage
        let audioDevicePriority: [String]
        let useSystemDefaultInput: Bool
        let microphoneWhenChargingUID: String?
        let microphoneOnBatteryUID: String?
        let recordingMediaHandlingMode: RecordingMediaHandlingMode
        let audioDuckingLevelPercent: Int
        let autoIncreaseMicrophoneVolume: Bool
        let removeSilenceBeforeProcessing: Bool
    }

    /// Loads audio and language settings.
    static func loadAudioAndLanguageSettings() -> AudioAndLanguageSettingsValues {
        let defaults = UserDefaults.standard
        let hasRecordingMediaHandlingMode = defaults.object(forKey: Keys.recordingMediaHandlingMode) != nil
        let hasDuckingEnabled = defaults.object(forKey: Keys.audioDuckingEnabled) != nil
        let hasDuckingLevel = defaults.object(forKey: Keys.audioDuckingLevelPercent) != nil

        let recordingMediaHandlingMode: RecordingMediaHandlingMode
        let audioDuckingLevelPercent: Int

        if hasRecordingMediaHandlingMode {
            recordingMediaHandlingMode = loadEnum(
                forKey: Keys.recordingMediaHandlingMode,
                defaultValue: .none
            )
            audioDuckingLevelPercent = AppSettingsStore.clampedAudioDuckingLevelPercent(
                loadInt(
                    forKey: Keys.audioDuckingLevelPercent,
                    defaultValue: defaultAudioDuckingLevelPercent
                )
            )
            defaults.set(recordingMediaHandlingMode.usesDucking, forKey: Keys.audioDuckingEnabled)
        } else if !hasDuckingEnabled,
                  !hasDuckingLevel,
                  defaults.bool(forKey: Keys.muteOutputDuringRecording)
        {
            // Preserve old behavior for migrated users that had output mute enabled.
            recordingMediaHandlingMode = .duckAudio
            audioDuckingLevelPercent = 0
            defaults.set(recordingMediaHandlingMode.rawValue, forKey: Keys.recordingMediaHandlingMode)
            defaults.set(recordingMediaHandlingMode.usesDucking, forKey: Keys.audioDuckingEnabled)
            defaults.set(audioDuckingLevelPercent, forKey: Keys.audioDuckingLevelPercent)
        } else {
            recordingMediaHandlingMode = loadBoolDefaultIfUnset(
                forKey: Keys.audioDuckingEnabled,
                defaultValue: false
            ) ? .duckAudio : .none
            audioDuckingLevelPercent = AppSettingsStore.clampedAudioDuckingLevelPercent(
                loadInt(
                    forKey: Keys.audioDuckingLevelPercent,
                    defaultValue: defaultAudioDuckingLevelPercent
                )
            )
            defaults.set(recordingMediaHandlingMode.rawValue, forKey: Keys.recordingMediaHandlingMode)
        }

        return AudioAndLanguageSettingsValues(
            selectedLanguage: loadEnum(forKey: Keys.selectedLanguage, defaultValue: .system),
            audioDevicePriority: UserDefaults.standard.stringArray(forKey: Keys.audioDevicePriority) ?? [],
            useSystemDefaultInput: loadBoolDefaultIfUnset(forKey: Keys.useSystemDefaultInput, defaultValue: true),
            microphoneWhenChargingUID: UserDefaults.standard.string(forKey: Keys.microphoneWhenChargingUID),
            microphoneOnBatteryUID: UserDefaults.standard.string(forKey: Keys.microphoneOnBatteryUID),
            recordingMediaHandlingMode: recordingMediaHandlingMode,
            audioDuckingLevelPercent: audioDuckingLevelPercent,
            autoIncreaseMicrophoneVolume: UserDefaults.standard.bool(forKey: Keys.autoIncreaseMicrophoneVolume),
            removeSilenceBeforeProcessing: loadBoolDefaultIfUnset(
                forKey: Keys.removeSilenceBeforeProcessing,
                defaultValue: false
            )
        )
    }
}

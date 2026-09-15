// swiftlint:disable large_tuple

import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain

extension AppSettingsStore {
    /// Struct for shortcut activation settings to avoid large tuple.
    struct ShortcutActivationSettingsValues {
        let shortcutActivationMode: ShortcutActivationMode
        let dictationShortcutActivationMode: ShortcutActivationMode
        let shortcutDoubleTapIntervalMilliseconds: Double
        let useEscapeToCancelRecording: Bool
        let selectedPresetKey: PresetShortcutKey
        let dictationSelectedPresetKey: PresetShortcutKey
        let meetingSelectedPresetKey: PresetShortcutKey
        let cancelRecordingShortcutDefinition: ShortcutDefinition?
    }

    /// Loads shortcut activation settings.
    static func loadShortcutActivationSettings() -> ShortcutActivationSettingsValues {
        let rawActivationMode = UserDefaults.standard.string(forKey: Keys.shortcutActivationMode)
        let resolvedActivationMode = rawActivationMode.flatMap { ShortcutActivationMode(rawValue: $0) } ?? .holdOrToggle

        let rawDictationActivationMode = UserDefaults.standard.string(forKey: Keys.dictationShortcutActivationMode)
        let dictationActivationMode = rawDictationActivationMode
            .flatMap { ShortcutActivationMode(rawValue: $0) }
            ?? resolvedActivationMode

        let rawPresetKey = UserDefaults.standard.string(forKey: Keys.selectedPresetKey)
        let presetKey = rawPresetKey.flatMap { PresetShortcutKey(rawValue: $0) } ?? .custom

        let rawDictationKey = UserDefaults.standard.string(forKey: Keys.dictationSelectedPresetKey)
        let dictationPresetKey = rawDictationKey.flatMap { PresetShortcutKey(rawValue: $0) }
            ?? (rawPresetKey.flatMap { PresetShortcutKey(rawValue: $0) } ?? .custom)

        let rawMeetingKey = UserDefaults.standard.string(forKey: Keys.meetingSelectedPresetKey)
        let meetingPresetKey = rawMeetingKey.flatMap { PresetShortcutKey(rawValue: $0) } ?? .custom

        return ShortcutActivationSettingsValues(
            shortcutActivationMode: resolvedActivationMode,
            dictationShortcutActivationMode: dictationActivationMode,
            shortcutDoubleTapIntervalMilliseconds: loadDouble(forKey: Keys.shortcutDoubleTapIntervalMilliseconds, defaultValue: defaultShortcutDoubleTapIntervalMilliseconds),
            useEscapeToCancelRecording: UserDefaults.standard.bool(forKey: Keys.useEscapeToCancelRecording),
            selectedPresetKey: presetKey,
            dictationSelectedPresetKey: dictationPresetKey,
            meetingSelectedPresetKey: meetingPresetKey,
            cancelRecordingShortcutDefinition: loadDecoded(
                ShortcutDefinition.self,
                forKey: Keys.cancelRecordingShortcutDefinition
            )
        )
    }

    /// Loads modifier shortcut gestures.
    static func loadModifierShortcutGestures() -> (
        dictation: ModifierShortcutGesture?,
        assistant: ModifierShortcutGesture?,
        meeting: ModifierShortcutGesture?
    ) {
        (
            loadDecoded(ModifierShortcutGesture.self, forKey: Keys.dictationModifierShortcutGesture),
            loadDecoded(ModifierShortcutGesture.self, forKey: Keys.assistantModifierShortcutGesture),
            loadDecoded(ModifierShortcutGesture.self, forKey: Keys.meetingModifierShortcutGesture)
        )
    }

    /// Struct for resolving shortcut definitions to avoid excessive parameters.
    struct ShortcutResolutionConfig {
        let dictationModifierGesture: ModifierShortcutGesture?
        let assistantModifierGesture: ModifierShortcutGesture?
        let meetingModifierGesture: ModifierShortcutGesture?
        let dictationPresetKey: PresetShortcutKey
        let assistantPresetKey: PresetShortcutKey
        let meetingPresetKey: PresetShortcutKey
        let dictationActivationMode: ShortcutActivationMode
        let assistantActivationMode: ShortcutActivationMode
        let shortcutActivationMode: ShortcutActivationMode
    }

    /// Resolves shortcut definitions from loaded values or legacy presets.
    static func resolveShortcutDefinitionsValues(
        from context: InitializationContext,
        config: ShortcutResolutionConfig
    ) -> (
        dictation: ShortcutDefinition?,
        assistant: ShortcutDefinition?,
        meeting: ShortcutDefinition?
    ) {
        (
            context.loadedDictationShortcutDefinition
                .flatMap {
                    normalizedInHouseShortcutDefinition(
                        $0,
                        activationMode: config.dictationActivationMode,
                        allowReturnOrEnter: false
                    )
                } ??
                resolveShortcutDefinition(
                    explicitGesture: config.dictationModifierGesture,
                    legacyPresetKey: config.dictationPresetKey,
                    activationMode: config.dictationActivationMode,
                    allowReturnOrEnter: false
                ) ??
                defaultDictationShortcutDefinition,
            context.loadedAssistantShortcutDefinition
                .flatMap {
                    normalizedInHouseShortcutDefinition(
                        $0,
                        activationMode: config.assistantActivationMode,
                        allowReturnOrEnter: false
                    )
                } ??
                resolveShortcutDefinition(
                    explicitGesture: config.assistantModifierGesture,
                    legacyPresetKey: config.assistantPresetKey,
                    activationMode: config.assistantActivationMode,
                    allowReturnOrEnter: false
                ) ??
                defaultAssistantShortcutDefinition,
            context.loadedMeetingShortcutDefinition
                .flatMap { normalizedInHouseShortcutDefinition($0, activationMode: config.shortcutActivationMode) } ??
                resolveShortcutDefinition(
                    explicitGesture: config.meetingModifierGesture,
                    legacyPresetKey: config.meetingPresetKey,
                    activationMode: config.shortcutActivationMode
                ) ??
                defaultMeetingShortcutDefinition
        )
    }
}

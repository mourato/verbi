import Foundation
import VerbiCoreCommon
import VerbiCoreDomain

// Initialization meeting and dictation - Carga de preferências de reunião e ditado
// Extraído de Initialization.swift para manter o arquivo abaixo do limite de
// tamanho, sem alterar a leitura de preferências.

extension AppSettingsStore {
    /// Loads meeting summary settings.
    static func loadMeetingSummarySettings() -> MeetingSummarySettingsValues {
        var prompts: [PostProcessingPrompt] = []
        if let data = UserDefaults.standard.data(forKey: Keys.meetingPrompts),
           let decoded = try? JSONDecoder().decode([PostProcessingPrompt].self, from: data)
        {
            prompts = decoded
        }

        let detectionMode = migrateMeetingDetectionModeIfNeeded()

        return MeetingSummarySettingsValues(
            meetingTypeAutoDetectEnabled: UserDefaults.standard.bool(forKey: Keys.meetingTypeAutoDetectEnabled),
            meetingSummaryOutputLanguage: loadEnum(forKey: Keys.meetingSummaryOutputLanguage, defaultValue: .original),
            meetingPrompts: prompts,
            summaryExportFolder: loadURLBookmark(forKey: Keys.summaryExportFolder),
            summaryTemplate: UserDefaults.standard.string(forKey: Keys.summaryTemplate) ?? defaultSummaryTemplate,
            summaryTemplateEnabled: loadBoolDefaultIfUnset(forKey: Keys.summaryTemplateEnabled, defaultValue: true),
            autoExportSummaries: UserDefaults.standard.bool(forKey: Keys.autoExportSummaries),
            summaryExportSafetyPolicyLevel: SummaryExportSafetyPolicyLevel(rawValue: UserDefaults.standard.string(forKey: Keys.summaryExportSafetyPolicyLevel) ?? "") ?? .standard,
            meetingNotesHotkeyEnabled: loadBoolDefaultIfUnset(forKey: Keys.meetingNotesHotkeyEnabled, defaultValue: true),
            meetingNotesShortcutDefinition: {
                guard UserDefaults.standard.object(forKey: Keys.meetingNotesShortcutDefinition) != nil else {
                    return defaultMeetingNotesShortcutDefinition
                }
                return loadDecoded(ShortcutDefinition.self, forKey: Keys.meetingNotesShortcutDefinition)
            }(),
            meetingNotesTranslucentPanel: loadBoolDefaultIfUnset(forKey: Keys.meetingNotesTranslucentPanel, defaultValue: true),
            meetingNotesShowOnAllSpaces: loadBoolDefaultIfUnset(forKey: Keys.meetingNotesShowOnAllSpaces, defaultValue: true),
            meetingNotesHideFromScreenCapture: UserDefaults.standard.bool(forKey: Keys.meetingNotesHideFromScreenCapture),
            meetingNotesAutoSizeHeight: loadBoolDefaultIfUnset(forKey: Keys.meetingNotesAutoSizeHeight, defaultValue: true),
            meetingNotesEditorTheme: UserDefaults.standard.string(forKey: Keys.meetingNotesEditorTheme) ?? "",
            meetingNotesTextSize: AppSettingsStore.normalizedMeetingNotesTextSize(
                UserDefaults.standard.object(forKey: Keys.meetingNotesTextSize) as? Int ?? AppSettingsStore.defaultMeetingNotesTextSize
            ),
            meetingNotesLastEditedCalendarEventIdentifier: UserDefaults.standard
                .string(forKey: Keys.meetingNotesLastEditedCalendarEventIdentifier),
            meetingQnAEnabled: loadBoolDefaultIfUnset(forKey: Keys.meetingQnAEnabled, defaultValue: true),
            meetingDetectionMode: detectionMode,
            meetingRemindersEnabled: detectionMode != .off,
            meetingReminderLeadMinutes: UserDefaults.standard.object(forKey: Keys.meetingReminderLeadMinutes) as? Int ?? 15,
            meetingReminderOverlayLeadSeconds: UserDefaults.standard.object(forKey: Keys.meetingReminderOverlayLeadSeconds) as? Int ?? 0,
            meetingReminderOverlayEnabled: loadBoolDefaultIfUnset(forKey: Keys.meetingReminderOverlayEnabled, defaultValue: true),
            meetingReminderAlertSoundEnabled: UserDefaults.standard.bool(forKey: Keys.meetingReminderAlertSoundEnabled),
            meetingReminderMirrorAllScreens: UserDefaults.standard.bool(forKey: Keys.meetingReminderMirrorAllScreens)
        )
    }

    /// Loads dictation rules and web targets.
    static func loadDictationRulesAndWebTargets(
        contextAwareness: ContextAwarenessSettingsValues,
        dictationSelection: EnhancementsAISelection,
        transcriptionSelection: TranscriptionProviderSelection = .default,
        inputLanguageCode: String? = nil,
        textHandlingPolicy: DictationTextHandlingPolicy = .init()
    ) -> DictationRulesAndWebTargetsValues {
        let defaultDictationStyle = defaultDictationStyle(
            contextAwarenessEnabled: contextAwareness.contextAwarenessEnabled,
            includeClipboard: contextAwareness.contextAwarenessIncludeClipboard,
            includeWindowOCR: contextAwareness.contextAwarenessIncludeWindowOCR,
            includeAccessibilityText: contextAwareness.contextAwarenessIncludeAccessibilityText,
            redactSensitiveData: contextAwareness.contextAwarenessRedactSensitiveData,
            dictationSelection: dictationSelection,
            textHandlingPolicy: textHandlingPolicy,
            transcriptionConfiguration: DictationTranscriptionConfiguration(
                selection: transcriptionSelection,
                inputLanguageCode: inputLanguageCode
            )
        )

        let loadedStyles = loadDecoded([DictationStyle].self, forKey: Keys.dictationStyles) ?? [defaultDictationStyle]
        let migratedStyles = migrateLegacyDictationStyles(
            loadedStyles,
            dictationSelection: dictationSelection,
            transcriptionSelection: transcriptionSelection,
            inputLanguageCode: inputLanguageCode,
            textHandlingPolicy: textHandlingPolicy
        )
        if migratedStyles != loadedStyles {
            if let data = try? JSONEncoder().encode(migratedStyles) {
                UserDefaults.standard.set(data, forKey: Keys.dictationStyles)
            }
        }

        return DictationRulesAndWebTargetsValues(
            markdownTargetBundleIdentifiers: loadDecoded([String].self, forKey: Keys.markdownTargetBundleIdentifiers) ?? defaultMarkdownTargetBundleIdentifiers,
            dictationAppRules: normalizedDictationAppRules(loadDecoded([DictationApplicationRule].self, forKey: Keys.dictationAppRules) ?? defaultDictationAppRules),
            dictationStyles: normalizedDictationStyles(
                migratedStyles,
                defaultStyle: defaultDictationStyle
            ),
            vocabularyReplacementRules: normalizedVocabularyReplacementRules(loadDecoded([VocabularyReplacementRule].self, forKey: Keys.vocabularyReplacementRules) ?? []),
            vocabularyTerms: normalizedVocabularyTerms(loadDecoded([VocabularyTerm].self, forKey: Keys.vocabularyTerms) ?? []),
            markdownWebTargets: loadDecoded([DictationWebContext].self, forKey: Keys.markdownWebTargets) ?? defaultMarkdownWebTargets,
            webTargetBrowserBundleIdentifiers: loadDecoded([String].self, forKey: Keys.webTargetBrowserBundleIdentifiers) ?? defaultWebTargetBrowserBundleIdentifiers,
            monitoredMeetingBundleIdentifiers: loadDecoded([String].self, forKey: Keys.monitoredMeetingBundleIdentifiers) ?? defaultMonitoredMeetingBundleIdentifiers,
            webMeetingTargets: loadDecoded([WebMeetingTarget].self, forKey: Keys.webMeetingTargets) ?? defaultWebMeetingTargets
        )
    }
}

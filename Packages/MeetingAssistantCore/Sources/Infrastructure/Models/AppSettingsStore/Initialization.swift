import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain

// MARK: - Initialization Helpers

extension AppSettingsStore {
    /// Holds temporarily loaded values during initialization to avoid multiple UserDefaults reads.
    struct InitializationContext {
        var loadedAIConfiguration: AIConfiguration
        var loadedEnhancementsSelection: EnhancementsAISelection
        var loadedDictationSelection: EnhancementsAISelection
        var loadedAssistantShortcutDefinition: ShortcutDefinition?
        var loadedDictationShortcutDefinition: ShortcutDefinition?
        var loadedMeetingShortcutDefinition: ShortcutDefinition?
        var loadedIntegrations: [AssistantIntegrationConfig]?
        var loadedContextAwarenessEnabled: Bool
        var hasPersistedLegacyPerTargetBrowsers: Bool
        var hasGlobalBrowserSetting: Bool
    }

    struct InitializationValues {
        let context: InitializationContext
        let ai: AIConfigurationValues
        let postProcessing: PostProcessingSettingsValues
        let capabilities: CapabilitySettingsValues
        let audio: AudioAndLanguageSettingsValues
        let shortcuts: ShortcutActivationSettingsValues
        let gestures: (
            dictation: ModifierShortcutGesture?,
            assistant: ModifierShortcutGesture?,
            meeting: ModifierShortcutGesture?,
        )
        let assistant: AssistantSettingsValues
        let meeting: MeetingSummarySettingsValues
        let contextAwareness: ContextAwarenessSettingsValues
        let dictation: DictationRulesAndWebTargetsValues
        let ui: UIAndIndicatorSettingsValues
        let smartSpacingAndCapitalizationEnabled: Bool
        let smartParagraphsEnabled: Bool
        let hasCompletedOnboarding: Bool
    }

    static func loadInitializationValues() -> InitializationValues {
        let context = createInitializationContext()
        let ai = loadAIConfigurationValues(from: context)
        let postProcessing = loadPostProcessingSettings()
        let capabilities = loadCapabilitySettings()
        let audio = loadAudioAndLanguageSettings()
        let smartSpacingAndCapitalizationEnabled = loadBoolDefaultIfUnset(
            forKey: Keys.smartSpacingAndCapitalizationEnabled,
            defaultValue: true,
        )
        let smartParagraphsEnabled = loadBoolDefaultIfUnset(
            forKey: Keys.smartParagraphsEnabled,
            defaultValue: true,
        )
        let shortcuts = loadShortcutActivationSettings()
        let gestures = loadModifierShortcutGestures()
        let assistant = loadAssistantSettings(from: context)
        let meeting = loadMeetingSummarySettings()
        let contextAwareness = loadContextAwarenessSettings(from: context)
        let dictation = loadDictationRulesAndWebTargets(
            contextAwareness: contextAwareness,
            dictationSelection: ai.enhancementsDictationAISelection,
            transcriptionSelection: ai.transcriptionDictationSelection,
            inputLanguageCode: postProcessing.transcriptionInputLanguageHint.languageCode,
            textHandlingPolicy: DictationTextHandlingPolicy(
                autoCopyToClipboard: UserDefaults.standard.object(forKey: "autoCopyTranscriptionToClipboard") == nil
                    ? true : UserDefaults.standard.bool(forKey: "autoCopyTranscriptionToClipboard"),
                autoPasteToActiveApp: UserDefaults.standard.bool(forKey: "autoPasteTranscriptionToActiveApp"),
                smartSpacingAndCapitalization: smartSpacingAndCapitalizationEnabled,
                smartParagraphs: smartParagraphsEnabled,
            ),
        )
        let ui = loadUIAndIndicatorSettings()
        let defaults = UserDefaults.standard

        return InitializationValues(
            context: context,
            ai: ai,
            postProcessing: postProcessing,
            capabilities: capabilities,
            audio: audio,
            shortcuts: shortcuts,
            gestures: gestures,
            assistant: assistant,
            meeting: meeting,
            contextAwareness: contextAwareness,
            dictation: dictation,
            ui: ui,
            smartSpacingAndCapitalizationEnabled: smartSpacingAndCapitalizationEnabled,
            smartParagraphsEnabled: smartParagraphsEnabled,
            hasCompletedOnboarding: defaults.bool(forKey: Keys.hasCompletedOnboarding),
        )
    }

    /// Creates the initialization context by loading all required values from UserDefaults.
    static func createInitializationContext() -> InitializationContext {
        migrateLegacyUserDefaultsDomainIfNeeded()

        let loadedAIConfiguration = loadAIConfiguration()
        let loadedEnhancementsSelection = loadEnhancementsAISelection(defaultingTo: loadedAIConfiguration)
        let loadedDictationSelection = loadEnhancementsDictationAISelection(defaultingTo: loadedEnhancementsSelection)

        let loadedAssistantShortcutDefinition = loadDecoded(
            ShortcutDefinition.self,
            forKey: Keys.assistantShortcutDefinition,
        )
        let loadedDictationShortcutDefinition = loadDecoded(
            ShortcutDefinition.self,
            forKey: Keys.dictationShortcutDefinition,
        )
        let loadedMeetingShortcutDefinition = loadDecoded(
            ShortcutDefinition.self,
            forKey: Keys.meetingShortcutDefinition,
        )

        let loadedIntegrations = loadDecoded([AssistantIntegrationConfig].self, forKey: Keys.assistantIntegrations)
        let loadedContextAwarenessEnabled = UserDefaults.standard.bool(forKey: Keys.contextAwarenessEnabled)

        let hasPersistedMarkdownWebTargets = UserDefaults.standard.object(forKey: Keys.markdownWebTargets) != nil
        let hasPersistedWebMeetingTargets = UserDefaults.standard.object(forKey: Keys.webMeetingTargets) != nil
        let hasPersistedLegacyPerTargetBrowsers = hasPersistedMarkdownWebTargets || hasPersistedWebMeetingTargets
        let hasGlobalBrowserSetting = UserDefaults.standard.object(forKey: Keys.webTargetBrowserBundleIdentifiers) != nil

        return InitializationContext(
            loadedAIConfiguration: loadedAIConfiguration,
            loadedEnhancementsSelection: loadedEnhancementsSelection,
            loadedDictationSelection: loadedDictationSelection,
            loadedAssistantShortcutDefinition: loadedAssistantShortcutDefinition,
            loadedDictationShortcutDefinition: loadedDictationShortcutDefinition,
            loadedMeetingShortcutDefinition: loadedMeetingShortcutDefinition,
            loadedIntegrations: loadedIntegrations,
            loadedContextAwarenessEnabled: loadedContextAwarenessEnabled,
            hasPersistedLegacyPerTargetBrowsers: hasPersistedLegacyPerTargetBrowsers,
            hasGlobalBrowserSetting: hasGlobalBrowserSetting,
        )
    }

    private static func migrateLegacyUserDefaultsDomainIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: AppIdentity.userDefaultsDomainMigrationFlag) else {
            return
        }

        let currentDomainName = Bundle.main.bundleIdentifier ?? AppIdentity.bundleIdentifier
        var currentDomain = defaults.persistentDomain(forName: currentDomainName) ?? [:]
        var didMerge = false

        for legacyDomainName in AppIdentity.legacyUserDefaultsDomains {
            guard let legacyDomain = defaults.persistentDomain(forName: legacyDomainName),
                  !legacyDomain.isEmpty
            else {
                continue
            }
            for (key, value) in legacyDomain where currentDomain[key] == nil {
                currentDomain[key] = value
                didMerge = true
            }
        }

        if didMerge {
            defaults.setPersistentDomain(currentDomain, forName: currentDomainName)
        }
        defaults.set(true, forKey: AppIdentity.userDefaultsDomainMigrationFlag)
    }

    struct CapabilitySettingsValues {
        let isMeetingTranscriptionEnabled: Bool
        let isAssistantEnabled: Bool
        let isAssistantIntegrationsEnabled: Bool
    }

    static func loadCapabilitySettings() -> CapabilitySettingsValues {
        CapabilitySettingsValues(
            isMeetingTranscriptionEnabled: loadCapabilityToggle(
                forKey: Keys.isMeetingTranscriptionEnabled,
                defaultForNewInstall: false,
                defaultForExistingInstall: true,
            ),
            isAssistantEnabled: loadCapabilityToggle(
                forKey: Keys.isAssistantEnabled,
                defaultForNewInstall: false,
                defaultForExistingInstall: true,
            ),
            isAssistantIntegrationsEnabled: loadCapabilityToggle(
                forKey: Keys.isAssistantIntegrationsEnabled,
                defaultForNewInstall: false,
                defaultForExistingInstall: true,
            ),
        )
    }

    /// Struct for assistant settings to avoid large tuple.
    struct AssistantSettingsValues {
        let assistantShortcutActivationMode: ShortcutActivationMode
        let assistantUseEscapeToCancelRecording: Bool
        let assistantUseEnterToStopRecording: Bool
        let assistantSelectedPresetKey: PresetShortcutKey
        let assistantIntegrations: [AssistantIntegrationConfig]
        let assistantSelectedIntegrationId: UUID?
        let assistantRaycastEnabled: Bool
        let assistantRaycastDeepLink: String
    }

    /// Loads assistant-specific settings.
    static func loadAssistantSettings(from context: InitializationContext) -> AssistantSettingsValues {
        let rawAssistantActivation = UserDefaults.standard.string(forKey: Keys.assistantShortcutActivationMode)
        let activationMode = rawAssistantActivation
            .flatMap { ShortcutActivationMode(rawValue: $0) } ?? .holdOrToggle

        let rawAssistantPresetKey = UserDefaults.standard.string(forKey: Keys.assistantSelectedPresetKey)
        let presetKey = rawAssistantPresetKey.flatMap { PresetShortcutKey(rawValue: $0) } ?? .custom

        let rawSelectedIntegrationId = UserDefaults.standard.string(forKey: Keys.assistantSelectedIntegrationId)

        return AssistantSettingsValues(
            assistantShortcutActivationMode: activationMode,
            assistantUseEscapeToCancelRecording: UserDefaults.standard.bool(forKey: Keys.assistantUseEscapeToCancelRecording),
            assistantUseEnterToStopRecording: false,
            assistantSelectedPresetKey: presetKey,
            assistantIntegrations: context.loadedIntegrations ?? [AssistantIntegrationConfig.defaultRaycast],
            assistantSelectedIntegrationId: rawSelectedIntegrationId.flatMap(UUID.init(uuidString:)),
            assistantRaycastEnabled: UserDefaults.standard.bool(forKey: Keys.assistantRaycastEnabled),
            assistantRaycastDeepLink: UserDefaults.standard.string(forKey: Keys.assistantRaycastDeepLink) ?? AssistantIntegrationConfig.defaultRaycastDeepLink,
        )
    }

    /// Struct for meeting summary settings to avoid large tuple.
    struct MeetingSummarySettingsValues {
        let meetingTypeAutoDetectEnabled: Bool
        let meetingSummaryOutputLanguage: DictationOutputLanguage
        let meetingPrompts: [PostProcessingPrompt]
        let summaryExportFolder: URL?
        let summaryTemplate: String
        let summaryTemplateEnabled: Bool
        let autoExportSummaries: Bool
        let summaryExportSafetyPolicyLevel: SummaryExportSafetyPolicyLevel
        let meetingNotesHotkeyEnabled: Bool
        let meetingNotesShortcutDefinition: ShortcutDefinition?
        let meetingNotesTranslucentPanel: Bool
        let meetingNotesShowOnAllSpaces: Bool
        let meetingNotesHideFromScreenCapture: Bool
        let meetingNotesAutoSizeHeight: Bool
        let meetingNotesEditorTheme: String
        let meetingNotesTextSize: Int
        let meetingNotesLastEditedCalendarEventIdentifier: String?
        let meetingQnAEnabled: Bool
        let meetingRemindersEnabled: Bool
        let meetingReminderLeadMinutes: Int
        let meetingReminderOverlayLeadSeconds: Int
        let meetingReminderOverlayEnabled: Bool
        let meetingReminderAlertSoundEnabled: Bool
        let meetingReminderMirrorAllScreens: Bool
    }

    /// Loads meeting summary settings.
    static func loadMeetingSummarySettings() -> MeetingSummarySettingsValues {
        var prompts: [PostProcessingPrompt] = []
        if let data = UserDefaults.standard.data(forKey: Keys.meetingPrompts),
           let decoded = try? JSONDecoder().decode([PostProcessingPrompt].self, from: data)
        {
            prompts = decoded
        }

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
                UserDefaults.standard.object(forKey: Keys.meetingNotesTextSize) as? Int ?? AppSettingsStore.defaultMeetingNotesTextSize,
            ),
            meetingNotesLastEditedCalendarEventIdentifier: UserDefaults.standard.string(
                forKey: Keys.meetingNotesLastEditedCalendarEventIdentifier,
            ),
            meetingQnAEnabled: loadBoolDefaultIfUnset(forKey: Keys.meetingQnAEnabled, defaultValue: true),
            meetingRemindersEnabled: loadBoolDefaultIfUnset(forKey: Keys.meetingRemindersEnabled, defaultValue: true),
            meetingReminderLeadMinutes: UserDefaults.standard.object(forKey: Keys.meetingReminderLeadMinutes) as? Int ?? 15,
            meetingReminderOverlayLeadSeconds: UserDefaults.standard.object(forKey: Keys.meetingReminderOverlayLeadSeconds) as? Int ?? 0,
            meetingReminderOverlayEnabled: loadBoolDefaultIfUnset(forKey: Keys.meetingReminderOverlayEnabled, defaultValue: true),
            meetingReminderAlertSoundEnabled: UserDefaults.standard.bool(forKey: Keys.meetingReminderAlertSoundEnabled),
            meetingReminderMirrorAllScreens: UserDefaults.standard.bool(forKey: Keys.meetingReminderMirrorAllScreens),
        )
    }

    /// Struct for context awareness settings to avoid large tuple.
    struct ContextAwarenessSettingsValues {
        let contextAwarenessEnabled: Bool
        let contextAwarenessIncludeClipboard: Bool
        let contextAwarenessIncludeWindowOCR: Bool
        let contextAwarenessIncludeAccessibilityText: Bool
        let contextAwarenessRedactSensitiveData: Bool
        let contextAwarenessExcludedBundleIDs: [String]
    }

    /// Loads context awareness settings.
    static func loadContextAwarenessSettings(from context: InitializationContext) -> ContextAwarenessSettingsValues {
        ContextAwarenessSettingsValues(
            contextAwarenessEnabled: context.loadedContextAwarenessEnabled,
            contextAwarenessIncludeClipboard: UserDefaults.standard.bool(forKey: Keys.contextAwarenessIncludeClipboard),
            contextAwarenessIncludeWindowOCR: UserDefaults.standard.bool(forKey: Keys.contextAwarenessIncludeWindowOCR),
            contextAwarenessIncludeAccessibilityText: loadBoolDefaultIfUnset(forKey: Keys.contextAwarenessIncludeAccessibilityText, defaultValue: true),
            contextAwarenessRedactSensitiveData: loadBoolDefaultIfUnset(forKey: Keys.contextAwarenessRedactSensitiveData, defaultValue: true),
            contextAwarenessExcludedBundleIDs: loadDecoded([String].self, forKey: Keys.contextAwarenessExcludedBundleIDs) ?? [],
        )
    }

    /// Struct for dictation rules and web targets to avoid large tuple.
    struct DictationRulesAndWebTargetsValues {
        let markdownTargetBundleIdentifiers: [String]
        let dictationAppRules: [DictationAppRule]
        let dictationStyles: [DictationStyle]
        let vocabularyReplacementRules: [VocabularyReplacementRule]
        let vocabularyTerms: [VocabularyTerm]
        let markdownWebTargets: [WebContextTarget]
        let webTargetBrowserBundleIdentifiers: [String]
        let monitoredMeetingBundleIdentifiers: [String]
        let webMeetingTargets: [WebMeetingTarget]
    }

    /// Loads dictation rules and web targets.
    static func loadDictationRulesAndWebTargets(
        contextAwareness: ContextAwarenessSettingsValues,
        dictationSelection: EnhancementsAISelection,
        transcriptionSelection: TranscriptionProviderSelection = .default,
        inputLanguageCode: String? = nil,
        textHandlingPolicy: DictationTextHandlingPolicy = .init(),
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
                inputLanguageCode: inputLanguageCode,
            ),
        )

        let loadedStyles = loadDecoded([DictationStyle].self, forKey: Keys.dictationStyles) ?? [defaultDictationStyle]
        let migratedStyles = migrateLegacyDictationStyles(
            loadedStyles,
            dictationSelection: dictationSelection,
            transcriptionSelection: transcriptionSelection,
            inputLanguageCode: inputLanguageCode,
            textHandlingPolicy: textHandlingPolicy,
        )
        if migratedStyles != loadedStyles {
            if let data = try? JSONEncoder().encode(migratedStyles) {
                UserDefaults.standard.set(data, forKey: Keys.dictationStyles)
            }
        }

        return DictationRulesAndWebTargetsValues(
            markdownTargetBundleIdentifiers: loadDecoded([String].self, forKey: Keys.markdownTargetBundleIdentifiers) ?? defaultMarkdownTargetBundleIdentifiers,
            dictationAppRules: normalizedDictationAppRules(loadDecoded([DictationAppRule].self, forKey: Keys.dictationAppRules) ?? defaultDictationAppRules),
            dictationStyles: normalizedDictationStyles(
                migratedStyles,
                defaultStyle: defaultDictationStyle,
            ),
            vocabularyReplacementRules: normalizedVocabularyReplacementRules(loadDecoded([VocabularyReplacementRule].self, forKey: Keys.vocabularyReplacementRules) ?? []),
            vocabularyTerms: normalizedVocabularyTerms(loadDecoded([VocabularyTerm].self, forKey: Keys.vocabularyTerms) ?? []),
            markdownWebTargets: loadDecoded([WebContextTarget].self, forKey: Keys.markdownWebTargets) ?? defaultMarkdownWebTargets,
            webTargetBrowserBundleIdentifiers: loadDecoded([String].self, forKey: Keys.webTargetBrowserBundleIdentifiers) ?? defaultWebTargetBrowserBundleIdentifiers,
            monitoredMeetingBundleIdentifiers: loadDecoded([String].self, forKey: Keys.monitoredMeetingBundleIdentifiers) ?? defaultMonitoredMeetingBundleIdentifiers,
            webMeetingTargets: loadDecoded([WebMeetingTarget].self, forKey: Keys.webMeetingTargets) ?? defaultWebMeetingTargets,
        )
    }

    /// Struct for UI and indicator settings to avoid large tuple.
    struct UIAndIndicatorSettingsValues {
        let assistantBorderColor: AssistantBorderColor
        let assistantBorderStyle: AssistantBorderStyle
        let assistantBorderWidth: Double
        let assistantGlowSize: Double
        let recordingIndicatorEnabled: Bool
        let recordingIndicatorStyle: RecordingIndicatorStyle
        let recordingIndicatorPosition: RecordingIndicatorPosition
        let recordingIndicatorAnimationSpeed: RecordingIndicatorAnimationSpeed
        let automaticAutomaticMeetingRecordingConfirmationDelay: AutomaticMeetingRecordingConfirmationDelay
        let autoDeleteTranscriptions: Bool
        let autoDeletePeriodDays: Int
        let appAccentColor: AppThemeColor
        let appearanceMode: AppearanceMode
        let soundFeedbackEnabled: Bool
        let recordingStartSound: SoundFeedbackSound
        let recordingStopSound: SoundFeedbackSound
        let showInDock: Bool
    }

    /// Loads UI and indicator settings.
    static func loadUIAndIndicatorSettings() -> UIAndIndicatorSettingsValues {
        let rawBorderColor = UserDefaults.standard.string(forKey: Keys.assistantBorderColor)
        let rawBorderStyle = UserDefaults.standard.string(forKey: Keys.assistantBorderStyle)
        let storedBorderWidth = UserDefaults.standard.object(forKey: Keys.assistantBorderWidth) as? NSNumber
        let storedGlowSize = UserDefaults.standard.object(forKey: Keys.assistantGlowSize) as? NSNumber

        let rawIndicatorStyle = UserDefaults.standard.string(forKey: Keys.recordingIndicatorStyle)
        let rawIndicatorPosition = UserDefaults.standard.string(forKey: Keys.recordingIndicatorPosition)
        let rawIndicatorAnimationSpeed = UserDefaults.standard.string(forKey: Keys.recordingIndicatorAnimationSpeed)
        let rawConfirmationDelay = UserDefaults.standard.object(
            forKey: Keys.automaticAutomaticMeetingRecordingConfirmationDelay,
        ) as? Int

        let rawDays = UserDefaults.standard.object(forKey: Keys.autoDeletePeriodDays) as? Int
        let rawAccentColor = UserDefaults.standard.string(forKey: Keys.appAccentColor)
        let rawAppearanceMode = UserDefaults.standard.string(forKey: Keys.appearanceMode)

        let rawStartSound = UserDefaults.standard.string(forKey: Keys.recordingStartSound)
        let rawStopSound = UserDefaults.standard.string(forKey: Keys.recordingStopSound)

        return UIAndIndicatorSettingsValues(
            assistantBorderColor: rawBorderColor.flatMap { AssistantBorderColor(rawValue: $0) } ?? .green,
            assistantBorderStyle: rawBorderStyle.flatMap { AssistantBorderStyle(rawValue: $0) } ?? .stroke,
            assistantBorderWidth: max(1, storedBorderWidth?.doubleValue ?? 8),
            assistantGlowSize: max(0, storedGlowSize?.doubleValue ?? 20),
            recordingIndicatorEnabled: loadBoolDefaultIfUnset(forKey: Keys.recordingIndicatorEnabled, defaultValue: true),
            recordingIndicatorStyle: rawIndicatorStyle.flatMap { RecordingIndicatorStyle(rawValue: $0) } ?? .mini,
            recordingIndicatorPosition: rawIndicatorPosition.flatMap { RecordingIndicatorPosition(rawValue: $0) } ?? .bottom,
            recordingIndicatorAnimationSpeed: rawIndicatorAnimationSpeed.flatMap { RecordingIndicatorAnimationSpeed(rawValue: $0) } ?? .normal,
            automaticAutomaticMeetingRecordingConfirmationDelay: rawConfirmationDelay
                .flatMap { AutomaticMeetingRecordingConfirmationDelay(rawValue: $0) } ?? .seconds3,
            autoDeleteTranscriptions: UserDefaults.standard.bool(forKey: Keys.autoDeleteTranscriptions),
            autoDeletePeriodDays: rawDays ?? 30,
            appAccentColor: rawAccentColor.flatMap { AppThemeColor(rawValue: $0) } ?? .system,
            appearanceMode: rawAppearanceMode.flatMap { AppearanceMode(rawValue: $0) } ?? .system,
            soundFeedbackEnabled: UserDefaults.standard.bool(forKey: Keys.soundFeedbackEnabled),
            recordingStartSound: rawStartSound.flatMap { SoundFeedbackSound(rawValue: $0) } ?? .pop,
            recordingStopSound: rawStopSound.flatMap { SoundFeedbackSound(rawValue: $0) } ?? .glass,
            showInDock: UserDefaults.standard.bool(forKey: Keys.showInDock),
        )
    }

    /// Finalizes initialization by performing migrations and saving initial state.
    func finalizeInitialization(context: InitializationContext) {
        // Resolve shortcut definitions
        let shortcutConfig = ShortcutResolutionConfig(
            dictationModifierGesture: dictationModifierShortcutGesture,
            assistantModifierGesture: assistantModifierShortcutGesture,
            meetingModifierGesture: meetingModifierShortcutGesture,
            dictationPresetKey: dictationSelectedPresetKey,
            assistantPresetKey: assistantSelectedPresetKey,
            meetingPresetKey: meetingSelectedPresetKey,
            dictationActivationMode: dictationShortcutActivationMode,
            assistantActivationMode: assistantShortcutActivationMode,
            shortcutActivationMode: shortcutActivationMode,
        )
        let defs = Self.resolveShortcutDefinitionsValues(
            from: context,
            config: shortcutConfig,
        )
        dictationShortcutDefinition = defs.dictation
        assistantShortcutDefinition = defs.assistant
        meetingShortcutDefinition = defs.meeting
        dictationModifierShortcutGesture = defs.dictation?.asModifierShortcutGesture
        assistantModifierShortcutGesture = defs.assistant?.asModifierShortcutGesture
        meetingModifierShortcutGesture = defs.meeting?.asModifierShortcutGesture

        if defs.dictation != nil {
            dictationSelectedPresetKey = .custom
            selectedPresetKey = .custom
        }
        if defs.assistant != nil {
            assistantSelectedPresetKey = .custom
        }
        if defs.meeting != nil {
            meetingSelectedPresetKey = .custom
        }

        if contextAwarenessEnabled {
            contextAwarenessIncludeAccessibilityText = true
        }

        let shouldMigrateLegacyAssistantIntegration = context.loadedIntegrations == nil
        if shouldMigrateLegacyAssistantIntegration {
            var migratedRaycast = AssistantIntegrationConfig.defaultRaycast
            migratedRaycast.isEnabled = assistantRaycastEnabled
            migratedRaycast.deepLink = AssistantIntegrationConfig.defaultRaycastDeepLink
            assistantIntegrations = [migratedRaycast]
            assistantSelectedIntegrationId = migratedRaycast.id
        }

        if assistantSelectedIntegrationId == nil {
            assistantSelectedIntegrationId = assistantIntegrations.first?.id
        }

        synchronizeAssistantIntegrationsState()
        save(assistantIntegrations, forKey: Keys.assistantIntegrations)

        if context.loadedDictationShortcutDefinition == nil {
            save(dictationShortcutDefinition, forKey: Keys.dictationShortcutDefinition)
        }
        if context.loadedAssistantShortcutDefinition == nil {
            save(assistantShortcutDefinition, forKey: Keys.assistantShortcutDefinition)
        }
        if context.loadedMeetingShortcutDefinition == nil {
            save(meetingShortcutDefinition, forKey: Keys.meetingShortcutDefinition)
        }

        if let selectedID = assistantSelectedIntegrationId {
            UserDefaults.standard.set(selectedID.uuidString, forKey: Keys.assistantSelectedIntegrationId)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.assistantSelectedIntegrationId)
        }

        UserDefaults.standard.set(assistantRaycastEnabled, forKey: Keys.assistantRaycastEnabled)
        UserDefaults.standard.set(assistantRaycastDeepLink, forKey: Keys.assistantRaycastDeepLink)
        UserDefaults.standard.removeObject(forKey: Keys.assistantUseEnterToStopRecording)

        if context.hasPersistedLegacyPerTargetBrowsers, !context.hasGlobalBrowserSetting {
            migrateWebTargetBrowsersToGlobalSettingIfNeeded()
        }

        migrateLegacyAudioDevicePriorityToPowerSelectionIfNeeded()
        migrateLegacyMarkdownTargetsToDictationAppRulesIfNeeded()
        migrateLegacyWebTargetBrowsersToDictationAppRulesIfNeeded()
        removeRetiredDictionaryQuickAddShortcutIfNeeded()
        backfillEnhancementsSelectionModelsIfNeeded()
        migrateEnhancementsProviderRegistrationAPIKeysIfNeeded()
        applyLanguage(selectedLanguage)
    }

    /// Drops the retired Dictionary quick-add shortcut key left behind after feature removal.
    public func removeRetiredDictionaryQuickAddShortcutIfNeeded() {
        UserDefaults.standard.removeObject(forKey: Keys.retiredDictionaryQuickAddShortcutDefinition)
    }

    public func migrateLegacyAudioDevicePriorityToPowerSelectionIfNeeded() {
        let defaults = UserDefaults.standard
        let hasChargingSelection = defaults.object(forKey: Keys.microphoneWhenChargingUID) != nil
        let hasBatterySelection = defaults.object(forKey: Keys.microphoneOnBatteryUID) != nil

        // If either setting was already configured, keep the user's explicit choices.
        guard !hasChargingSelection, !hasBatterySelection else { return }

        guard let firstLegacyUID = audioDevicePriority.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !firstLegacyUID.isEmpty
        else {
            return
        }

        microphoneWhenChargingUID = firstLegacyUID
        microphoneOnBatteryUID = firstLegacyUID
    }
}

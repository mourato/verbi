import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain

public extension AppSettingsStore {
    /// Reset all settings to defaults.
    // swiftlint:disable:next function_body_length
    func resetToDefaults() {
        aiConfiguration = .default
        enhancementsAISelection = .default
        enhancementsDictationAISelection = .default
        enhancementsProviderSelectedModels = [:]
        enhancementsProviderRegistrations = []
        enhancementsProviderSelectedModelsByRegistration = [:]
        transcriptionDictationSelection = .default
        transcriptionProviderSelectedModels = [:]
        meetingTranscriptionLocalModel = .parakeetTdt06BV3
        systemPrompt = AIPromptTemplates.defaultSystemPrompt
        userPrompts = []
        dictationPrompts = []
        deletedPromptIds = []
        selectedPromptId = nil
        dictationSelectedPromptId = nil
        postProcessingEnabled = false
        dictationStructuredPostProcessingEnabled = false
        isDiarizationEnabled = false
        modelResidencyTimeout = .minutes30
        isMeetingTranscriptionEnabled = false
        isAssistantEnabled = false
        isAssistantIntegrationsEnabled = false
        transcriptionInputLanguageHint = .automatic
        minSpeakers = nil
        maxSpeakers = nil
        numSpeakers = nil
        audioDevicePriority = []
        useSystemDefaultInput = true
        microphoneWhenChargingUID = nil
        microphoneOnBatteryUID = nil
        recordingMediaHandlingMode = .none
        audioDuckingLevelPercent = Self.defaultAudioDuckingLevelPercent
        autoIncreaseMicrophoneVolume = false
        removeSilenceBeforeProcessing = false
        smartSpacingAndCapitalizationEnabled = true
        smartParagraphsEnabled = true
        shortcutActivationMode = .holdOrToggle
        dictationShortcutActivationMode = .holdOrToggle
        shortcutDoubleTapIntervalMilliseconds = Self.defaultShortcutDoubleTapIntervalMilliseconds
        useEscapeToCancelRecording = false
        selectedPresetKey = .custom
        dictationShortcutDefinition = Self.defaultDictationShortcutDefinition
        assistantShortcutDefinition = Self.defaultAssistantShortcutDefinition
        meetingShortcutDefinition = Self.defaultMeetingShortcutDefinition
        cancelRecordingShortcutDefinition = nil
        dictationModifierShortcutGesture = nil
        assistantModifierShortcutGesture = nil
        meetingModifierShortcutGesture = nil
        assistantShortcutActivationMode = .holdOrToggle
        assistantUseEscapeToCancelRecording = false
        assistantUseEnterToStopRecording = false
        assistantSelectedPresetKey = .custom
        dictationSelectedPresetKey = .custom
        meetingSelectedPresetKey = .custom
        assistantBorderColor = .green
        assistantBorderStyle = .stroke
        assistantBorderWidth = 8
        assistantGlowSize = 20
        assistantIntegrations = [AssistantIntegrationConfig.defaultRaycast]
        assistantSelectedIntegrationId = AssistantIntegrationConfig.defaultRaycast.id
        assistantRaycastEnabled = false
        assistantRaycastDeepLink = AssistantIntegrationConfig.defaultRaycastDeepLink
        recordingIndicatorEnabled = true
        recordingIndicatorStyle = .mini
        recordingIndicatorPosition = .bottom
        recordingIndicatorAnimationSpeed = .normal
        automaticAutomaticMeetingRecordingConfirmationDelay = .seconds3
        autoDeleteTranscriptions = false
        autoDeletePeriodDays = 30
        appAccentColor = .system
        appearanceMode = .system
        soundFeedbackEnabled = false
        recordingStartSound = .pop
        recordingStopSound = .glass
        launchAtLogin = false
        showInDock = false
        meetingPrompts = []
        meetingTypeAutoDetectEnabled = false
        meetingSummaryOutputLanguage = .original
        summaryTemplateEnabled = true
        summaryExportSafetyPolicyLevel = .standard
        meetingNotesHotkeyEnabled = true
        meetingNotesShortcutDefinition = Self.defaultMeetingNotesShortcutDefinition
        meetingNotesTranslucentPanel = true
        meetingNotesShowOnAllSpaces = true
        meetingNotesHideFromScreenCapture = false
        meetingNotesAutoSizeHeight = true
        meetingNotesEditorTheme = ""
        meetingNotesTextSize = Self.defaultMeetingNotesTextSize
        meetingNotesLastEditedCalendarEventIdentifier = nil
        meetingQnAEnabled = true
        resetMeetingReminderDefaults()
        markdownTargetBundleIdentifiers = Self.defaultMarkdownTargetBundleIdentifiers
        dictationAppRules = Self.defaultDictationAppRules
        dictationStyles = [defaultDictationStyle()]
        vocabularyReplacementRules = []
        vocabularyTerms = []
        markdownWebTargets = Self.defaultMarkdownWebTargets
        webTargetBrowserBundleIdentifiers = Self.defaultWebTargetBrowserBundleIdentifiers
        monitoredMeetingBundleIdentifiers = Self.defaultMonitoredMeetingBundleIdentifiers
        webMeetingTargets = Self.defaultWebMeetingTargets

        UserDefaults.standard.removeObject(forKey: Keys.muteOutputDuringRecording)
    }

    private func defaultDictationStyle() -> DictationStyle {
        Self.defaultDictationStyle(
            contextAwarenessEnabled: contextAwarenessEnabled,
            includeClipboard: contextAwarenessIncludeClipboard,
            includeWindowOCR: contextAwarenessIncludeWindowOCR,
            includeAccessibilityText: contextAwarenessIncludeAccessibilityText,
            redactSensitiveData: contextAwarenessRedactSensitiveData,
            dictationSelection: enhancementsDictationAISelection,
        )
    }
}

import AppKit
import Foundation
import SwiftUI
import VerbiCoreCommon
import VerbiCoreDomain

// swiftlint:disable file_length type_body_length

@MainActor
public class AppSettingsStore: ObservableObject {
    public static let shared = AppSettingsStore()

    public static func clampedAudioDuckingLevelPercent(_ value: Int) -> Int {
        max(0, min(100, value))
    }

    public static let noPostProcessingPromptId: UUID = {
        guard let uuid = UUID(uuidString: "00000000-0000-0000-0000-000000000001") else {
            assertionFailure("Invalid UUID string for noPostProcessingPromptId")
            return UUID()
        }
        return uuid
    }()

    var isSynchronizingAssistantIntegrations = false

    @Published public var aiConfiguration: AIConfiguration {
        didSet { save(aiConfiguration, forKey: Keys.aiConfiguration) }
    }

    @Published public var enhancementsAISelection: EnhancementsAISelection {
        didSet { save(enhancementsAISelection, forKey: Keys.enhancementsAISelection) }
    }

    @Published public var enhancementsDictationAISelection: EnhancementsAISelection {
        didSet { save(enhancementsDictationAISelection, forKey: Keys.enhancementsDictationAISelection) }
    }

    @Published public var enhancementsProviderSelectedModels: [String: String] {
        didSet { save(enhancementsProviderSelectedModels, forKey: Keys.enhancementsProviderSelectedModels) }
    }

    @Published public var enhancementsProviderRegistrations: [EnhancementsProviderRegistration] {
        didSet { save(enhancementsProviderRegistrations, forKey: Keys.enhancementsProviderRegistrations) }
    }

    @Published public var enhancementsProviderSelectedModelsByRegistration: [String: String] {
        didSet {
            save(
                enhancementsProviderSelectedModelsByRegistration,
                forKey: Keys.enhancementsProviderSelectedModelsByRegistration
            )
        }
    }

    @Published public var transcriptionDictationSelection: TranscriptionProviderSelection {
        didSet { save(transcriptionDictationSelection, forKey: Keys.transcriptionDictationSelection) }
    }

    @Published public var transcriptionProviderSelectedModels: [String: String] {
        didSet { save(transcriptionProviderSelectedModels, forKey: Keys.transcriptionProviderSelectedModels) }
    }

    @Published public var meetingTranscriptionLocalModel: LocalTranscriptionModel {
        didSet {
            UserDefaults.standard.set(
                meetingTranscriptionLocalModel.rawValue,
                forKey: Keys.meetingTranscriptionLocalModel
            )
        }
    }

    @Published public var systemPrompt: String {
        didSet { UserDefaults.standard.set(systemPrompt, forKey: Keys.systemPrompt) }
    }

    @Published public var userPrompts: [PostProcessingPrompt] {
        didSet { save(userPrompts, forKey: Keys.userPrompts) }
    }

    @Published public var deletedPromptIds: Set<UUID> {
        didSet { save(deletedPromptIds, forKey: Keys.deletedPromptIds) }
    }

    @Published public var selectedPromptId: UUID? {
        didSet {
            if let id = selectedPromptId {
                UserDefaults.standard.set(id.uuidString, forKey: Keys.selectedPromptId)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.selectedPromptId)
            }
        }
    }

    @Published public var dictationPrompts: [PostProcessingPrompt] {
        didSet { save(dictationPrompts, forKey: Keys.dictationPrompts) }
    }

    @Published public var meetingPrompts: [PostProcessingPrompt] {
        didSet { save(meetingPrompts, forKey: Keys.meetingPrompts) }
    }

    @Published public var dictationSelectedPromptId: UUID? {
        didSet {
            if let id = dictationSelectedPromptId {
                UserDefaults.standard.set(id.uuidString, forKey: Keys.dictationSelectedPromptId)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.dictationSelectedPromptId)
            }
        }
    }

    @Published public var postProcessingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(postProcessingEnabled, forKey: Keys.postProcessingEnabled)
        }
    }

    @Published public var dictationStructuredPostProcessingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(
                dictationStructuredPostProcessingEnabled,
                forKey: Keys.dictationStructuredPostProcessingEnabled
            )
        }
    }

    @Published public var isDiarizationEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isDiarizationEnabled, forKey: Keys.isDiarizationEnabled)
        }
    }

    @Published public var modelResidencyTimeout: ModelResidencyTimeoutOption {
        didSet {
            UserDefaults.standard.set(modelResidencyTimeout.rawValue, forKey: Keys.modelResidencyTimeout)
        }
    }

    @Published public var isMeetingTranscriptionEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isMeetingTranscriptionEnabled, forKey: Keys.isMeetingTranscriptionEnabled)
        }
    }

    @Published public var isAssistantEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAssistantEnabled, forKey: Keys.isAssistantEnabled)
        }
    }

    @Published public var isAssistantIntegrationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAssistantIntegrationsEnabled, forKey: Keys.isAssistantIntegrationsEnabled)
        }
    }

    @Published public var transcriptionInputLanguageHint: TranscriptionInputLanguageHint {
        didSet {
            UserDefaults.standard.set(
                transcriptionInputLanguageHint.rawValue,
                forKey: Keys.transcriptionInputLanguageHint
            )
        }
    }

    @Published public var minSpeakers: Int? {
        didSet {
            UserDefaults.standard.set(minSpeakers, forKey: Keys.minSpeakers)
        }
    }

    @Published public var maxSpeakers: Int? {
        didSet {
            UserDefaults.standard.set(maxSpeakers, forKey: Keys.maxSpeakers)
        }
    }

    @Published public var numSpeakers: Int? {
        didSet {
            UserDefaults.standard.set(numSpeakers, forKey: Keys.numSpeakers)
        }
    }

    @Published public var audioFormat: AudioFormat {
        didSet {
            UserDefaults.standard.set(audioFormat.rawValue, forKey: PostProcessingKeys.audioFormat)
        }
    }

    @Published public var shouldMergeAudioFiles: Bool {
        didSet {
            UserDefaults.standard.set(shouldMergeAudioFiles, forKey: PostProcessingKeys.shouldMergeAudioFiles)
        }
    }

    @Published public var selectedLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: Keys.selectedLanguage)
            applyLanguage(selectedLanguage)
        }
    }

    @Published public var audioDevicePriority: [String] {
        didSet { save(audioDevicePriority, forKey: Keys.audioDevicePriority) }
    }

    @Published public var useSystemDefaultInput: Bool {
        didSet { UserDefaults.standard.set(useSystemDefaultInput, forKey: Keys.useSystemDefaultInput) }
    }

    @Published public var microphoneWhenChargingUID: String? {
        didSet { UserDefaults.standard.set(microphoneWhenChargingUID, forKey: Keys.microphoneWhenChargingUID) }
    }

    @Published public var microphoneOnBatteryUID: String? {
        didSet { UserDefaults.standard.set(microphoneOnBatteryUID, forKey: Keys.microphoneOnBatteryUID) }
    }

    @Published public var recordingMediaHandlingMode: RecordingMediaHandlingMode {
        didSet {
            UserDefaults.standard.set(recordingMediaHandlingMode.rawValue, forKey: Keys.recordingMediaHandlingMode)
            UserDefaults.standard.set(recordingMediaHandlingMode.usesDucking, forKey: Keys.audioDuckingEnabled)
        }
    }

    public var audioDuckingEnabled: Bool {
        get { recordingMediaHandlingMode.usesDucking }
        set { recordingMediaHandlingMode = newValue ? .duckAudio : .none }
    }

    @Published public var audioDuckingLevelPercent: Int {
        didSet {
            let clamped = Self.clampedAudioDuckingLevelPercent(audioDuckingLevelPercent)
            guard clamped == audioDuckingLevelPercent else {
                audioDuckingLevelPercent = clamped
                return
            }

            UserDefaults.standard.set(audioDuckingLevelPercent, forKey: Keys.audioDuckingLevelPercent)
        }
    }

    @Published public var autoIncreaseMicrophoneVolume: Bool {
        didSet { UserDefaults.standard.set(autoIncreaseMicrophoneVolume, forKey: Keys.autoIncreaseMicrophoneVolume) }
    }

    @Published public var removeSilenceBeforeProcessing: Bool {
        didSet {
            UserDefaults.standard.set(removeSilenceBeforeProcessing, forKey: Keys.removeSilenceBeforeProcessing)
        }
    }

    @Published public var shortcutActivationMode: ShortcutActivationMode {
        didSet { UserDefaults.standard.set(shortcutActivationMode.rawValue, forKey: Keys.shortcutActivationMode) }
    }

    @Published public var dictationShortcutActivationMode: ShortcutActivationMode {
        didSet { UserDefaults.standard.set(dictationShortcutActivationMode.rawValue, forKey: Keys.dictationShortcutActivationMode) }
    }

    @Published public var shortcutDoubleTapIntervalMilliseconds: Double {
        didSet {
            UserDefaults.standard.set(
                shortcutDoubleTapIntervalMilliseconds,
                forKey: Keys.shortcutDoubleTapIntervalMilliseconds
            )
        }
    }

    @Published public var smartSpacingAndCapitalizationEnabled: Bool {
        didSet { UserDefaults.standard.set(smartSpacingAndCapitalizationEnabled, forKey: Keys.smartSpacingAndCapitalizationEnabled) }
    }

    @Published public var smartParagraphsEnabled: Bool {
        didSet { UserDefaults.standard.set(smartParagraphsEnabled, forKey: Keys.smartParagraphsEnabled) }
    }

    @Published public var useEscapeToCancelRecording: Bool {
        didSet { UserDefaults.standard.set(useEscapeToCancelRecording, forKey: Keys.useEscapeToCancelRecording) }
    }

    @Published public var selectedPresetKey: PresetShortcutKey {
        didSet { UserDefaults.standard.set(selectedPresetKey.rawValue, forKey: Keys.selectedPresetKey) }
    }

    @Published public var dictationSelectedPresetKey: PresetShortcutKey {
        didSet { UserDefaults.standard.set(dictationSelectedPresetKey.rawValue, forKey: Keys.dictationSelectedPresetKey) }
    }

    @Published public var meetingSelectedPresetKey: PresetShortcutKey {
        didSet { UserDefaults.standard.set(meetingSelectedPresetKey.rawValue, forKey: Keys.meetingSelectedPresetKey) }
    }

    @Published public var dictationShortcutDefinition: ShortcutDefinition? {
        didSet { save(dictationShortcutDefinition, forKey: Keys.dictationShortcutDefinition) }
    }

    @Published public var assistantShortcutDefinition: ShortcutDefinition? {
        didSet { save(assistantShortcutDefinition, forKey: Keys.assistantShortcutDefinition) }
    }

    @Published public var meetingShortcutDefinition: ShortcutDefinition? {
        didSet { save(meetingShortcutDefinition, forKey: Keys.meetingShortcutDefinition) }
    }

    @Published public var cancelRecordingShortcutDefinition: ShortcutDefinition? {
        didSet { save(cancelRecordingShortcutDefinition, forKey: Keys.cancelRecordingShortcutDefinition) }
    }

    @Published public var vocabularyTeachShortcutDefinition: ShortcutDefinition? {
        didSet { save(vocabularyTeachShortcutDefinition, forKey: Keys.vocabularyTeachShortcutDefinition) }
    }

    @Published public var dictationModifierShortcutGesture: ModifierShortcutGesture? {
        didSet { save(dictationModifierShortcutGesture, forKey: Keys.dictationModifierShortcutGesture) }
    }

    @Published public var assistantModifierShortcutGesture: ModifierShortcutGesture? {
        didSet { save(assistantModifierShortcutGesture, forKey: Keys.assistantModifierShortcutGesture) }
    }

    @Published public var meetingModifierShortcutGesture: ModifierShortcutGesture? {
        didSet { save(meetingModifierShortcutGesture, forKey: Keys.meetingModifierShortcutGesture) }
    }

    @Published public var assistantShortcutActivationMode: ShortcutActivationMode {
        didSet {
            UserDefaults.standard.set(
                assistantShortcutActivationMode.rawValue,
                forKey: Keys.assistantShortcutActivationMode
            )
        }
    }

    @Published public var assistantUseEscapeToCancelRecording: Bool {
        didSet { UserDefaults.standard.set(assistantUseEscapeToCancelRecording, forKey: Keys.assistantUseEscapeToCancelRecording) }
    }

    @Published public var assistantUseEnterToStopRecording: Bool {
        didSet { UserDefaults.standard.set(assistantUseEnterToStopRecording, forKey: Keys.assistantUseEnterToStopRecording) }
    }

    @Published public var assistantSelectedPresetKey: PresetShortcutKey {
        didSet { UserDefaults.standard.set(assistantSelectedPresetKey.rawValue, forKey: Keys.assistantSelectedPresetKey) }
    }

    @Published public var assistantBorderColor: AssistantBorderColor {
        didSet { UserDefaults.standard.set(assistantBorderColor.rawValue, forKey: Keys.assistantBorderColor) }
    }

    @Published public var assistantBorderStyle: AssistantBorderStyle {
        didSet { UserDefaults.standard.set(assistantBorderStyle.rawValue, forKey: Keys.assistantBorderStyle) }
    }

    @Published public var assistantBorderWidth: Double {
        didSet { UserDefaults.standard.set(assistantBorderWidth, forKey: Keys.assistantBorderWidth) }
    }

    @Published public var assistantGlowSize: Double {
        didSet { UserDefaults.standard.set(assistantGlowSize, forKey: Keys.assistantGlowSize) }
    }

    @Published public var assistantIntegrations: [AssistantIntegrationConfig] {
        didSet {
            guard !isSynchronizingAssistantIntegrations else { return }
            synchronizeAssistantIntegrationsState()
            save(assistantIntegrations, forKey: Keys.assistantIntegrations)
        }
    }

    @Published public var assistantSelectedIntegrationId: UUID? {
        didSet {
            if let id = assistantSelectedIntegrationId {
                UserDefaults.standard.set(id.uuidString, forKey: Keys.assistantSelectedIntegrationId)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.assistantSelectedIntegrationId)
            }
        }
    }

    @Published public var assistantRaycastEnabled: Bool {
        didSet { UserDefaults.standard.set(assistantRaycastEnabled, forKey: Keys.assistantRaycastEnabled) }
    }

    @Published public var assistantRaycastDeepLink: String {
        didSet { UserDefaults.standard.set(assistantRaycastDeepLink, forKey: Keys.assistantRaycastDeepLink) }
    }

    @Published public var meetingTypeAutoDetectEnabled: Bool {
        didSet { UserDefaults.standard.set(meetingTypeAutoDetectEnabled, forKey: Keys.meetingTypeAutoDetectEnabled) }
    }

    @Published public var meetingSummaryOutputLanguage: DictationOutputLanguage {
        didSet { UserDefaults.standard.set(meetingSummaryOutputLanguage.rawValue, forKey: Keys.meetingSummaryOutputLanguage) }
    }

    @Published public var summaryExportFolder: URL? {
        didSet {
            if let url = summaryExportFolder {
                do {
                    let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    UserDefaults.standard.set(bookmark, forKey: Keys.summaryExportFolder)
                } catch {
                    print("Failed to save bookmark for export folder: \(error)")
                }
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.summaryExportFolder)
            }
        }
    }

    @Published public var summaryTemplate: String {
        didSet { UserDefaults.standard.set(summaryTemplate, forKey: Keys.summaryTemplate) }
    }

    @Published public var summaryTemplateEnabled: Bool {
        didSet { UserDefaults.standard.set(summaryTemplateEnabled, forKey: Keys.summaryTemplateEnabled) }
    }

    @Published public var autoExportSummaries: Bool {
        didSet { UserDefaults.standard.set(autoExportSummaries, forKey: Keys.autoExportSummaries) }
    }

    @Published public var summaryExportSafetyPolicyLevel: SummaryExportSafetyPolicyLevel {
        didSet { UserDefaults.standard.set(summaryExportSafetyPolicyLevel.rawValue, forKey: Keys.summaryExportSafetyPolicyLevel) }
    }

    @Published public var meetingNotesHotkeyEnabled: Bool {
        didSet { UserDefaults.standard.set(meetingNotesHotkeyEnabled, forKey: Keys.meetingNotesHotkeyEnabled) }
    }

    @Published public var meetingNotesShortcutDefinition: ShortcutDefinition? {
        didSet {
            if let meetingNotesShortcutDefinition {
                save(meetingNotesShortcutDefinition, forKey: Keys.meetingNotesShortcutDefinition)
            } else if let data = try? JSONEncoder().encode(ShortcutDefinition?.none) {
                UserDefaults.standard.set(data, forKey: Keys.meetingNotesShortcutDefinition)
            }
        }
    }

    @Published public var meetingNotesTranslucentPanel: Bool {
        didSet { UserDefaults.standard.set(meetingNotesTranslucentPanel, forKey: Keys.meetingNotesTranslucentPanel) }
    }

    @Published public var meetingNotesShowOnAllSpaces: Bool {
        didSet { UserDefaults.standard.set(meetingNotesShowOnAllSpaces, forKey: Keys.meetingNotesShowOnAllSpaces) }
    }

    @Published public var meetingNotesHideFromScreenCapture: Bool {
        didSet { UserDefaults.standard.set(meetingNotesHideFromScreenCapture, forKey: Keys.meetingNotesHideFromScreenCapture) }
    }

    @Published public var meetingNotesAutoSizeHeight: Bool {
        didSet { UserDefaults.standard.set(meetingNotesAutoSizeHeight, forKey: Keys.meetingNotesAutoSizeHeight) }
    }

    @Published public var meetingNotesEditorTheme: String {
        didSet { UserDefaults.standard.set(meetingNotesEditorTheme, forKey: Keys.meetingNotesEditorTheme) }
    }

    @Published public var meetingNotesTextSize: Int {
        didSet {
            let normalized = Self.normalizedMeetingNotesTextSize(meetingNotesTextSize)
            if normalized != meetingNotesTextSize {
                meetingNotesTextSize = normalized
                return
            }
            UserDefaults.standard.set(normalized, forKey: Keys.meetingNotesTextSize)
        }
    }

    @Published public var meetingNotesLastEditedCalendarEventIdentifier: String? {
        didSet {
            if let meetingNotesLastEditedCalendarEventIdentifier {
                UserDefaults.standard.set(
                    meetingNotesLastEditedCalendarEventIdentifier,
                    forKey: Keys.meetingNotesLastEditedCalendarEventIdentifier
                )
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.meetingNotesLastEditedCalendarEventIdentifier)
            }
        }
    }

    @Published public var meetingQnAEnabled: Bool {
        didSet { UserDefaults.standard.set(meetingQnAEnabled, forKey: Keys.meetingQnAEnabled) }
    }

    @Published public var meetingDetectionMode: MeetingDetectionMode {
        didSet {
            UserDefaults.standard.set(meetingDetectionMode.rawValue, forKey: Keys.meetingDetectionMode)
            UserDefaults.standard.set(true, forKey: Keys.meetingDetectionModeMigrated)
            syncLegacyMeetingDetectionSettings(for: meetingDetectionMode)
        }
    }

    @Published public var meetingRemindersEnabled: Bool {
        didSet { UserDefaults.standard.set(meetingRemindersEnabled, forKey: Keys.meetingRemindersEnabled) }
    }

    @Published public var meetingReminderLeadMinutes: Int {
        didSet { UserDefaults.standard.set(meetingReminderLeadMinutes, forKey: Keys.meetingReminderLeadMinutes) }
    }

    @Published public var meetingReminderOverlayLeadSeconds: Int {
        didSet { UserDefaults.standard.set(meetingReminderOverlayLeadSeconds, forKey: Keys.meetingReminderOverlayLeadSeconds) }
    }

    @Published public var meetingReminderOverlayEnabled: Bool {
        didSet { UserDefaults.standard.set(meetingReminderOverlayEnabled, forKey: Keys.meetingReminderOverlayEnabled) }
    }

    @Published public var meetingReminderAlertSoundEnabled: Bool {
        didSet { UserDefaults.standard.set(meetingReminderAlertSoundEnabled, forKey: Keys.meetingReminderAlertSoundEnabled) }
    }

    @Published public var meetingReminderMirrorAllScreens: Bool {
        didSet { UserDefaults.standard.set(meetingReminderMirrorAllScreens, forKey: Keys.meetingReminderMirrorAllScreens) }
    }

    @Published public var contextAwarenessEnabled: Bool {
        didSet {
            UserDefaults.standard.set(contextAwarenessEnabled, forKey: Keys.contextAwarenessEnabled)
            if contextAwarenessEnabled {
                contextAwarenessIncludeAccessibilityText = true
            }
        }
    }

    @Published public var contextAwarenessIncludeClipboard: Bool {
        didSet { UserDefaults.standard.set(contextAwarenessIncludeClipboard, forKey: Keys.contextAwarenessIncludeClipboard) }
    }

    @Published public var contextAwarenessIncludeWindowOCR: Bool {
        didSet { UserDefaults.standard.set(contextAwarenessIncludeWindowOCR, forKey: Keys.contextAwarenessIncludeWindowOCR) }
    }

    @Published public var contextAwarenessIncludeAccessibilityText: Bool {
        didSet { UserDefaults.standard.set(contextAwarenessIncludeAccessibilityText, forKey: Keys.contextAwarenessIncludeAccessibilityText) }
    }

    @Published public var contextAwarenessRedactSensitiveData: Bool {
        didSet { UserDefaults.standard.set(contextAwarenessRedactSensitiveData, forKey: Keys.contextAwarenessRedactSensitiveData) }
    }

    @Published public var contextAwarenessExcludedBundleIDs: [String] {
        didSet { save(contextAwarenessExcludedBundleIDs, forKey: Keys.contextAwarenessExcludedBundleIDs) }
    }

    @Published public var markdownTargetBundleIdentifiers: [String] {
        didSet { save(markdownTargetBundleIdentifiers, forKey: Keys.markdownTargetBundleIdentifiers) }
    }

    @Published public var dictationAppRules: [DictationApplicationRule] {
        didSet {
            let normalizedRules = Self.normalizedDictationAppRules(dictationAppRules)
            if normalizedRules != dictationAppRules {
                dictationAppRules = normalizedRules
                return
            }

            save(dictationAppRules, forKey: Keys.dictationAppRules)

            let markdownTargets = dictationAppRules
                .filter(\.forceMarkdownOutput)
                .map(\.bundleIdentifier)

            if markdownTargets != markdownTargetBundleIdentifiers {
                markdownTargetBundleIdentifiers = markdownTargets
            }

            let synchronizedBrowsers = synchronizedWebTargetBrowsers(
                from: dictationAppRules,
                legacyBrowsers: webTargetBrowserBundleIdentifiers
            )

            if synchronizedBrowsers != webTargetBrowserBundleIdentifiers {
                webTargetBrowserBundleIdentifiers = synchronizedBrowsers
            }
        }
    }

    @Published public var dictationStyles: [DictationStyle] {
        didSet {
            let normalizedStyles = Self.normalizedDictationStyles(
                dictationStyles,
                defaultStyle: currentDefaultDictationStyle()
            )
            if normalizedStyles != dictationStyles {
                dictationStyles = normalizedStyles
                return
            }

            save(dictationStyles, forKey: Keys.dictationStyles)
        }
    }

    @Published public var vocabularyReplacementRules: [VocabularyReplacementRule] {
        didSet {
            let normalizedRules = Self.normalizedVocabularyReplacementRules(vocabularyReplacementRules)
            if normalizedRules != vocabularyReplacementRules {
                vocabularyReplacementRules = normalizedRules
                return
            }

            save(vocabularyReplacementRules, forKey: Keys.vocabularyReplacementRules)
        }
    }

    @Published public var vocabularyTerms: [VocabularyTerm] {
        didSet {
            let normalizedTerms = Self.normalizedVocabularyTerms(vocabularyTerms)
            if normalizedTerms != vocabularyTerms {
                vocabularyTerms = normalizedTerms
                return
            }

            save(vocabularyTerms, forKey: Keys.vocabularyTerms)
        }
    }

    @Published public var markdownWebTargets: [DictationWebContext] {
        didSet { save(markdownWebTargets, forKey: Keys.markdownWebTargets) }
    }

    @Published public var webTargetBrowserBundleIdentifiers: [String] {
        didSet { save(webTargetBrowserBundleIdentifiers, forKey: Keys.webTargetBrowserBundleIdentifiers) }
    }

    @Published public var monitoredMeetingBundleIdentifiers: [String] {
        didSet { save(monitoredMeetingBundleIdentifiers, forKey: Keys.monitoredMeetingBundleIdentifiers) }
    }

    @Published public var webMeetingTargets: [WebMeetingTarget] {
        didSet { save(webMeetingTargets, forKey: Keys.webMeetingTargets) }
    }

    @Published public var recordingIndicatorEnabled: Bool {
        didSet { UserDefaults.standard.set(recordingIndicatorEnabled, forKey: Keys.recordingIndicatorEnabled) }
    }

    @Published public var recordingIndicatorPosition: RecordingIndicatorPosition {
        didSet { UserDefaults.standard.set(recordingIndicatorPosition.rawValue, forKey: Keys.recordingIndicatorPosition) }
    }

    @Published public var recordingIndicatorAnimationSpeed: RecordingIndicatorAnimationSpeed {
        didSet {
            UserDefaults.standard.set(
                recordingIndicatorAnimationSpeed.rawValue,
                forKey: Keys.recordingIndicatorAnimationSpeed
            )
        }
    }

    @Published public var automaticRecordingConfirmationDelay: AutomaticMeetingRecordingConfirmationDelay {
        didSet {
            let defaults = UserDefaults.standard
            let rawValue = automaticRecordingConfirmationDelay.rawValue
            defaults.set(rawValue, forKey: Keys.automaticRecordingConfirmationDelay)
            defaults.set(rawValue, forKey: Keys.legacyAutomaticConfirmationDelay)
        }
    }

    @available(*, deprecated, renamed: "automaticRecordingConfirmationDelay")
    // justified: preserve deprecated public API compatibility; swiftlint:disable:next identifier_name
    public var automaticAutomaticMeetingRecordingConfirmationDelay: AutomaticMeetingRecordingConfirmationDelay {
        get { automaticRecordingConfirmationDelay }
        set { automaticRecordingConfirmationDelay = newValue }
    }

    @Published public var autoDeleteTranscriptions: Bool {
        didSet { UserDefaults.standard.set(autoDeleteTranscriptions, forKey: Keys.autoDeleteTranscriptions) }
    }

    @Published public var autoDeletePeriodDays: Int {
        didSet { UserDefaults.standard.set(autoDeletePeriodDays, forKey: Keys.autoDeletePeriodDays) }
    }

    @Published public var appAccentColor: AppThemeColor {
        didSet { UserDefaults.standard.set(appAccentColor.rawValue, forKey: Keys.appAccentColor) }
    }

    @Published public var soundFeedbackEnabled: Bool {
        didSet { UserDefaults.standard.set(soundFeedbackEnabled, forKey: Keys.soundFeedbackEnabled) }
    }

    @Published public var soundFeedbackCue: SoundFeedbackCue {
        didSet { UserDefaults.standard.set(soundFeedbackCue.rawValue, forKey: Keys.soundFeedbackCue) }
    }

    @Published public var soundFeedbackVolume: Float {
        didSet {
            let clamped = SoundFeedbackCue.clampedVolume(soundFeedbackVolume)
            if clamped != soundFeedbackVolume {
                soundFeedbackVolume = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: Keys.soundFeedbackVolume)
        }
    }

    @Published public var recordingStartSound: SoundFeedbackSound {
        didSet { UserDefaults.standard.set(recordingStartSound.rawValue, forKey: Keys.recordingStartSound) }
    }

    @Published public var recordingStopSound: SoundFeedbackSound {
        didSet { UserDefaults.standard.set(recordingStopSound.rawValue, forKey: Keys.recordingStopSound) }
    }

    @Published public var showInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showInMenuBar, forKey: Keys.showInMenuBar) }
    }

    @Published public var showInDock: Bool {
        didSet { UserDefaults.standard.set(showInDock, forKey: Keys.showInDock) }
    }

    @Published public var appearanceMode: AppearanceMode {
        didSet { UserDefaults.standard.set(appearanceMode.rawValue, forKey: Keys.appearanceMode) }
    }

    @Published public var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    // swiftlint:disable:next function_body_length
    private init() {
        let values = Self.loadInitializationValues()
        let context = values.context
        let ai = values.ai
        aiConfiguration = ai.aiConfiguration
        enhancementsAISelection = ai.enhancementsAISelection
        enhancementsDictationAISelection = ai.enhancementsDictationAISelection
        enhancementsProviderSelectedModels = ai.enhancementsProviderSelectedModels
        enhancementsProviderRegistrations = ai.enhancementsProviderRegistrations
        enhancementsProviderSelectedModelsByRegistration = ai.enhancementsProviderSelectedModelsByRegistration
        transcriptionDictationSelection = ai.transcriptionDictationSelection
        transcriptionProviderSelectedModels = ai.transcriptionProviderSelectedModels
        meetingTranscriptionLocalModel = ai.meetingTranscriptionLocalModel

        let postProcessing = values.postProcessing
        systemPrompt = postProcessing.systemPrompt
        userPrompts = postProcessing.userPrompts
        dictationPrompts = postProcessing.dictationPrompts
        deletedPromptIds = postProcessing.deletedPromptIds
        postProcessingEnabled = postProcessing.postProcessingEnabled
        dictationStructuredPostProcessingEnabled = postProcessing.dictationStructuredPostProcessingEnabled
        isDiarizationEnabled = postProcessing.isDiarizationEnabled
        modelResidencyTimeout = postProcessing.modelResidencyTimeout
        transcriptionInputLanguageHint = postProcessing.transcriptionInputLanguageHint
        (minSpeakers, maxSpeakers, numSpeakers) = (postProcessing.minSpeakers, postProcessing.maxSpeakers, postProcessing.numSpeakers)
        audioFormat = postProcessing.audioFormat
        selectedPromptId = postProcessing.selectedPromptId
        dictationSelectedPromptId = postProcessing.dictationSelectedPromptId
        shouldMergeAudioFiles = postProcessing.shouldMergeAudioFiles

        let capabilities = values.capabilities
        (isMeetingTranscriptionEnabled, isAssistantEnabled, isAssistantIntegrationsEnabled) = (
            capabilities.isMeetingTranscriptionEnabled,
            capabilities.isAssistantEnabled,
            capabilities.isAssistantIntegrationsEnabled
        )

        let audioSettings = values.audio
        (selectedLanguage, audioDevicePriority) = (audioSettings.selectedLanguage, audioSettings.audioDevicePriority)
        useSystemDefaultInput = audioSettings.useSystemDefaultInput
        (microphoneWhenChargingUID, microphoneOnBatteryUID) = (audioSettings.microphoneWhenChargingUID, audioSettings.microphoneOnBatteryUID)
        recordingMediaHandlingMode = audioSettings.recordingMediaHandlingMode
        audioDuckingLevelPercent = audioSettings.audioDuckingLevelPercent
        autoIncreaseMicrophoneVolume = audioSettings.autoIncreaseMicrophoneVolume
        removeSilenceBeforeProcessing = audioSettings.removeSilenceBeforeProcessing
        smartSpacingAndCapitalizationEnabled = values.smartSpacingAndCapitalizationEnabled
        smartParagraphsEnabled = values.smartParagraphsEnabled

        let shortcuts = values.shortcuts
        (shortcutActivationMode, dictationShortcutActivationMode) = (
            shortcuts.shortcutActivationMode,
            shortcuts.dictationShortcutActivationMode
        )
        shortcutDoubleTapIntervalMilliseconds = shortcuts.shortcutDoubleTapIntervalMilliseconds
        useEscapeToCancelRecording = shortcuts.useEscapeToCancelRecording
        (selectedPresetKey, dictationSelectedPresetKey, meetingSelectedPresetKey) = (
            shortcuts.selectedPresetKey,
            shortcuts.dictationSelectedPresetKey,
            shortcuts.meetingSelectedPresetKey
        )
        cancelRecordingShortcutDefinition = shortcuts.cancelRecordingShortcutDefinition
        vocabularyTeachShortcutDefinition = shortcuts.vocabularyTeachShortcutDefinition

        let gestures = values.gestures
        (dictationModifierShortcutGesture, assistantModifierShortcutGesture, meetingModifierShortcutGesture) = (
            gestures.dictation,
            gestures.assistant,
            gestures.meeting
        )

        let assistant = values.assistant
        assistantShortcutActivationMode = assistant.assistantShortcutActivationMode
        assistantUseEscapeToCancelRecording = assistant.assistantUseEscapeToCancelRecording
        assistantUseEnterToStopRecording = assistant.assistantUseEnterToStopRecording
        assistantSelectedPresetKey = assistant.assistantSelectedPresetKey
        assistantIntegrations = assistant.assistantIntegrations
        assistantSelectedIntegrationId = assistant.assistantSelectedIntegrationId
        (assistantRaycastEnabled, assistantRaycastDeepLink) = (assistant.assistantRaycastEnabled, assistant.assistantRaycastDeepLink)

        let meeting = values.meeting
        meetingTypeAutoDetectEnabled = meeting.meetingTypeAutoDetectEnabled
        meetingSummaryOutputLanguage = meeting.meetingSummaryOutputLanguage
        meetingPrompts = meeting.meetingPrompts
        summaryExportFolder = meeting.summaryExportFolder
        summaryTemplate = meeting.summaryTemplate
        summaryTemplateEnabled = meeting.summaryTemplateEnabled
        autoExportSummaries = meeting.autoExportSummaries
        summaryExportSafetyPolicyLevel = meeting.summaryExportSafetyPolicyLevel
        meetingQnAEnabled = meeting.meetingQnAEnabled
        meetingNotesHotkeyEnabled = meeting.meetingNotesHotkeyEnabled
        meetingNotesShortcutDefinition = meeting.meetingNotesShortcutDefinition
        meetingNotesTranslucentPanel = meeting.meetingNotesTranslucentPanel
        meetingNotesShowOnAllSpaces = meeting.meetingNotesShowOnAllSpaces
        meetingNotesHideFromScreenCapture = meeting.meetingNotesHideFromScreenCapture
        meetingNotesAutoSizeHeight = meeting.meetingNotesAutoSizeHeight
        meetingNotesEditorTheme = meeting.meetingNotesEditorTheme
        meetingNotesTextSize = meeting.meetingNotesTextSize
        meetingNotesLastEditedCalendarEventIdentifier = meeting.meetingNotesLastEditedCalendarEventIdentifier
        meetingDetectionMode = meeting.meetingDetectionMode
        meetingRemindersEnabled = meeting.meetingRemindersEnabled
        meetingReminderLeadMinutes = meeting.meetingReminderLeadMinutes
        meetingReminderOverlayLeadSeconds = meeting.meetingReminderOverlayLeadSeconds
        meetingReminderOverlayEnabled = meeting.meetingReminderOverlayEnabled
        meetingReminderAlertSoundEnabled = meeting.meetingReminderAlertSoundEnabled
        meetingReminderMirrorAllScreens = meeting.meetingReminderMirrorAllScreens

        let ctx = values.contextAwareness
        contextAwarenessEnabled = ctx.contextAwarenessEnabled
        (contextAwarenessIncludeClipboard, contextAwarenessIncludeWindowOCR) = (
            ctx.contextAwarenessIncludeClipboard,
            ctx.contextAwarenessIncludeWindowOCR
        )
        contextAwarenessIncludeAccessibilityText = ctx.contextAwarenessIncludeAccessibilityText
        contextAwarenessRedactSensitiveData = ctx.contextAwarenessRedactSensitiveData
        contextAwarenessExcludedBundleIDs = ctx.contextAwarenessExcludedBundleIDs

        let dict = values.dictation
        markdownTargetBundleIdentifiers = dict.markdownTargetBundleIdentifiers
        dictationAppRules = dict.dictationAppRules
        dictationStyles = dict.dictationStyles
        vocabularyReplacementRules = dict.vocabularyReplacementRules
        vocabularyTerms = dict.vocabularyTerms
        markdownWebTargets = dict.markdownWebTargets
        webTargetBrowserBundleIdentifiers = dict.webTargetBrowserBundleIdentifiers
        monitoredMeetingBundleIdentifiers = dict.monitoredMeetingBundleIdentifiers
        webMeetingTargets = dict.webMeetingTargets

        let uiSettings = values.ui
        assistantBorderColor = uiSettings.assistantBorderColor
        assistantBorderStyle = uiSettings.assistantBorderStyle
        assistantBorderWidth = uiSettings.assistantBorderWidth
        assistantGlowSize = uiSettings.assistantGlowSize
        recordingIndicatorEnabled = uiSettings.recordingIndicatorEnabled
        recordingIndicatorPosition = uiSettings.recordingIndicatorPosition
        recordingIndicatorAnimationSpeed = uiSettings.recordingIndicatorAnimationSpeed
        automaticRecordingConfirmationDelay = uiSettings.automaticRecordingConfirmationDelay
        autoDeleteTranscriptions = uiSettings.autoDeleteTranscriptions
        autoDeletePeriodDays = uiSettings.autoDeletePeriodDays
        appAccentColor = uiSettings.appAccentColor
        appearanceMode = uiSettings.appearanceMode
        soundFeedbackEnabled = uiSettings.soundFeedbackEnabled
        soundFeedbackCue = uiSettings.soundFeedbackCue
        soundFeedbackVolume = uiSettings.soundFeedbackVolume
        recordingStartSound = uiSettings.recordingStartSound
        recordingStopSound = uiSettings.recordingStopSound
        showInMenuBar = uiSettings.showInMenuBar
        showInDock = uiSettings.showInDock
        hasCompletedOnboarding = values.hasCompletedOnboarding

        finalizeInitialization(context: context)
    }
}

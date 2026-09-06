import AppKit
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import SwiftUI

// swiftlint:disable file_length type_body_length

// MARK: - App Settings Store

/// Centralized settings manager using UserDefaults.
@MainActor
public class AppSettingsStore: ObservableObject {
    public static let shared = AppSettingsStore()

    public static func clampedAudioDuckingLevelPercent(_ value: Int) -> Int {
        max(0, min(100, value))
    }

    /// Sentinel UUID used to represent an explicit "No post-processing" selection.
    /// This avoids changing persisted schemas while still allowing an opt-out choice.
    public static let noPostProcessingPromptId: UUID = {
        guard let uuid = UUID(uuidString: "00000000-0000-0000-0000-000000000001") else {
            assertionFailure("Invalid UUID string for noPostProcessingPromptId")
            return UUID()
        }
        return uuid
    }()

    var isSynchronizingAssistantIntegrations = false

    // MARK: - Published Properties

    @Published public var aiConfiguration: AIConfiguration {
        didSet { save(aiConfiguration, forKey: Keys.aiConfiguration) }
    }

    /// Provider/model selection for meeting intelligence features.
    @Published public var enhancementsAISelection: EnhancementsAISelection {
        didSet { save(enhancementsAISelection, forKey: Keys.enhancementsAISelection) }
    }

    /// Provider/model selection for dictation intelligence features.
    /// Assistant mode reuses this selection automatically.
    @Published public var enhancementsDictationAISelection: EnhancementsAISelection {
        didSet { save(enhancementsDictationAISelection, forKey: Keys.enhancementsDictationAISelection) }
    }

    /// Per-provider model selection used by provider cards in Enhancements setup.
    /// Keys are `AIProvider.rawValue`.
    @Published public var enhancementsProviderSelectedModels: [String: String] {
        didSet { save(enhancementsProviderSelectedModels, forKey: Keys.enhancementsProviderSelectedModels) }
    }

    /// Registered providers available for Enhancements post-processing setup.
    @Published public var enhancementsProviderRegistrations: [EnhancementsProviderRegistration] {
        didSet { save(enhancementsProviderRegistrations, forKey: Keys.enhancementsProviderRegistrations) }
    }

    /// Per-registration model selection used by Enhancements setup.
    /// Keys are `EnhancementsProviderRegistration.id.uuidString`.
    @Published public var enhancementsProviderSelectedModelsByRegistration: [String: String] {
        didSet {
            save(
                enhancementsProviderSelectedModelsByRegistration,
                forKey: Keys.enhancementsProviderSelectedModelsByRegistration,
            )
        }
    }

    /// Provider/model selection for dictation and assistant transcription flows.
    @Published public var transcriptionDictationSelection: TranscriptionProviderSelection {
        didSet { save(transcriptionDictationSelection, forKey: Keys.transcriptionDictationSelection) }
    }

    /// Per-provider model selection for transcription providers.
    /// Keys are `TranscriptionProvider.rawValue`.
    @Published public var transcriptionProviderSelectedModels: [String: String] {
        didSet { save(transcriptionProviderSelectedModels, forKey: Keys.transcriptionProviderSelectedModels) }
    }

    /// Dedicated local transcription model used by meeting transcription.
    @Published public var meetingTranscriptionLocalModel: LocalTranscriptionModel {
        didSet {
            UserDefaults.standard.set(
                meetingTranscriptionLocalModel.rawValue,
                forKey: Keys.meetingTranscriptionLocalModel,
            )
        }
    }

    // MARK: - Post-Processing Properties

    /// Custom system prompt for post-processing.
    @Published public var systemPrompt: String {
        didSet { UserDefaults.standard.set(systemPrompt, forKey: Keys.systemPrompt) }
    }

    /// User-created prompts for post-processing.
    @Published public var userPrompts: [PostProcessingPrompt] {
        didSet { save(userPrompts, forKey: Keys.userPrompts) }
    }

    /// Predefined prompt IDs that the user has explicitly deleted.
    @Published public var deletedPromptIds: Set<UUID> {
        didSet { save(deletedPromptIds, forKey: Keys.deletedPromptIds) }
    }

    /// Currently selected prompt ID for post-processing.
    @Published public var selectedPromptId: UUID? {
        didSet {
            if let id = selectedPromptId {
                UserDefaults.standard.set(id.uuidString, forKey: Keys.selectedPromptId)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.selectedPromptId)
            }
        }
    }

    /// User-created prompts specifically for dictation.
    @Published public var dictationPrompts: [PostProcessingPrompt] {
        didSet { save(dictationPrompts, forKey: Keys.dictationPrompts) }
    }

    /// User-created prompts specifically for meetings.
    @Published public var meetingPrompts: [PostProcessingPrompt] {
        didSet { save(meetingPrompts, forKey: Keys.meetingPrompts) }
    }

    /// Selected prompt ID for dictation post-processing.
    @Published public var dictationSelectedPromptId: UUID? {
        didSet {
            if let id = dictationSelectedPromptId {
                UserDefaults.standard.set(id.uuidString, forKey: Keys.dictationSelectedPromptId)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.dictationSelectedPromptId)
            }
        }
    }

    /// Whether post-processing is enabled.
    @Published public var postProcessingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(postProcessingEnabled, forKey: Keys.postProcessingEnabled)
        }
    }

    /// Whether dictation should use the structured JSON post-processing pipeline.
    /// Default: false (fast direct pipeline).
    @Published public var dictationStructuredPostProcessingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(
                dictationStructuredPostProcessingEnabled,
                forKey: Keys.dictationStructuredPostProcessingEnabled,
            )
        }
    }

    /// Whether speaker diarization is enabled.
    @Published public var isDiarizationEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isDiarizationEnabled, forKey: Keys.isDiarizationEnabled)
        }
    }

    /// Configures how long local models remain in RAM after last use.
    @Published public var modelResidencyTimeout: ModelResidencyTimeoutOption {
        didSet {
            UserDefaults.standard.set(modelResidencyTimeout.rawValue, forKey: Keys.modelResidencyTimeout)
        }
    }

    /// Controls whether meeting transcription features are available.
    /// New installs default to disabled for lower runtime footprint.
    @Published public var isMeetingTranscriptionEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isMeetingTranscriptionEnabled, forKey: Keys.isMeetingTranscriptionEnabled)
        }
    }

    /// Controls whether assistant features are available.
    /// New installs default to disabled for lower runtime footprint.
    @Published public var isAssistantEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAssistantEnabled, forKey: Keys.isAssistantEnabled)
        }
    }

    /// Controls whether assistant third-party integrations are available.
    /// New installs default to disabled for lower runtime footprint.
    @Published public var isAssistantIntegrationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAssistantIntegrationsEnabled, forKey: Keys.isAssistantIntegrationsEnabled)
        }
    }

    /// Optional language hint used by transcription providers to improve speech recognition accuracy.
    @Published public var transcriptionInputLanguageHint: TranscriptionInputLanguageHint {
        didSet {
            UserDefaults.standard.set(
                transcriptionInputLanguageHint.rawValue,
                forKey: Keys.transcriptionInputLanguageHint,
            )
        }
    }

    /// Minimum number of speakers for diarization.
    @Published public var minSpeakers: Int? {
        didSet {
            UserDefaults.standard.set(minSpeakers, forKey: Keys.minSpeakers)
        }
    }

    /// Maximum number of speakers for diarization.
    @Published public var maxSpeakers: Int? {
        didSet {
            UserDefaults.standard.set(maxSpeakers, forKey: Keys.maxSpeakers)
        }
    }

    /// Fixed number of speakers for diarization.
    @Published public var numSpeakers: Int? {
        didSet {
            UserDefaults.standard.set(numSpeakers, forKey: Keys.numSpeakers)
        }
    }

    /// Selected audio format for recordings.
    @Published public var audioFormat: AudioFormat {
        didSet {
            UserDefaults.standard.set(audioFormat.rawValue, forKey: PostProcessingKeys.audioFormat)
        }
    }

    /// Whether to merge audio files after recording.
    /// Default: true
    @Published public var shouldMergeAudioFiles: Bool {
        didSet {
            UserDefaults.standard.set(shouldMergeAudioFiles, forKey: PostProcessingKeys.shouldMergeAudioFiles)
        }
    }

    /// Selected app language.
    @Published public var selectedLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: Keys.selectedLanguage)
            applyLanguage(selectedLanguage)
        }
    }

    /// Ordered list of audio device UIDs by priority.
    @Published public var audioDevicePriority: [String] {
        didSet { save(audioDevicePriority, forKey: Keys.audioDevicePriority) }
    }

    /// Whether to use the system default input device instead of a custom priority list.
    @Published public var useSystemDefaultInput: Bool {
        didSet { UserDefaults.standard.set(useSystemDefaultInput, forKey: Keys.useSystemDefaultInput) }
    }

    /// Custom microphone UID used while the Mac is connected to power.
    @Published public var microphoneWhenChargingUID: String? {
        didSet { UserDefaults.standard.set(microphoneWhenChargingUID, forKey: Keys.microphoneWhenChargingUID) }
    }

    /// Custom microphone UID used while the Mac is running on battery.
    @Published public var microphoneOnBatteryUID: String? {
        didSet { UserDefaults.standard.set(microphoneOnBatteryUID, forKey: Keys.microphoneOnBatteryUID) }
    }

    /// How currently playing media should be handled for microphone-only recordings.
    @Published public var recordingMediaHandlingMode: RecordingMediaHandlingMode {
        didSet {
            UserDefaults.standard.set(recordingMediaHandlingMode.rawValue, forKey: Keys.recordingMediaHandlingMode)
            UserDefaults.standard.set(recordingMediaHandlingMode.usesDucking, forKey: Keys.audioDuckingEnabled)
        }
    }

    /// Backward-compatible facade used by legacy callers and tests.
    public var audioDuckingEnabled: Bool {
        get { recordingMediaHandlingMode.usesDucking }
        set { recordingMediaHandlingMode = newValue ? .duckAudio : .none }
    }

    /// Target percentage of the current system output volume while recording.
    /// 0 means full mute, 100 keeps current output volume unchanged.
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

    /// Whether to set the default microphone input volume to maximum when recording starts.
    @Published public var autoIncreaseMicrophoneVolume: Bool {
        didSet { UserDefaults.standard.set(autoIncreaseMicrophoneVolume, forKey: Keys.autoIncreaseMicrophoneVolume) }
    }

    /// Whether silence should be removed from a temporary audio copy before transcription.
    @Published public var removeSilenceBeforeProcessing: Bool {
        didSet {
            UserDefaults.standard.set(removeSilenceBeforeProcessing, forKey: Keys.removeSilenceBeforeProcessing)
        }
    }

    /// How keyboard shortcuts activate recording.
    @Published public var shortcutActivationMode: ShortcutActivationMode {
        didSet { UserDefaults.standard.set(shortcutActivationMode.rawValue, forKey: Keys.shortcutActivationMode) }
    }

    /// How keyboard shortcuts activate Dictation.
    @Published public var dictationShortcutActivationMode: ShortcutActivationMode {
        didSet { UserDefaults.standard.set(dictationShortcutActivationMode.rawValue, forKey: Keys.dictationShortcutActivationMode) }
    }

    /// Double-tap window applied globally to all shortcut handlers.
    @Published public var shortcutDoubleTapIntervalMilliseconds: Double {
        didSet {
            UserDefaults.standard.set(
                shortcutDoubleTapIntervalMilliseconds,
                forKey: Keys.shortcutDoubleTapIntervalMilliseconds,
            )
        }
    }

    /// Adjusts spacing and capitalization before delivering dictation text.
    @Published public var smartSpacingAndCapitalizationEnabled: Bool {
        didSet { UserDefaults.standard.set(smartSpacingAndCapitalizationEnabled, forKey: Keys.smartSpacingAndCapitalizationEnabled) }
    }

    /// Breaks long dictated text into paragraphs before delivery.
    @Published public var smartParagraphsEnabled: Bool {
        didSet { UserDefaults.standard.set(smartParagraphsEnabled, forKey: Keys.smartParagraphsEnabled) }
    }

    /// Whether pressing Escape cancels recording.
    @Published public var useEscapeToCancelRecording: Bool {
        didSet { UserDefaults.standard.set(useEscapeToCancelRecording, forKey: Keys.useEscapeToCancelRecording) }
    }

    /// Selected preset shortcut key for recording activation.
    @Published public var selectedPresetKey: PresetShortcutKey {
        didSet { UserDefaults.standard.set(selectedPresetKey.rawValue, forKey: Keys.selectedPresetKey) }
    }

    /// Selected preset shortcut key for Dictation activation.
    @Published public var dictationSelectedPresetKey: PresetShortcutKey {
        didSet { UserDefaults.standard.set(dictationSelectedPresetKey.rawValue, forKey: Keys.dictationSelectedPresetKey) }
    }

    /// Selected preset shortcut key for Meetings activation.
    @Published public var meetingSelectedPresetKey: PresetShortcutKey {
        didSet { UserDefaults.standard.set(meetingSelectedPresetKey.rawValue, forKey: Keys.meetingSelectedPresetKey) }
    }

    /// Canonical in-house shortcut definition for Dictation.
    @Published public var dictationShortcutDefinition: ShortcutDefinition? {
        didSet { save(dictationShortcutDefinition, forKey: Keys.dictationShortcutDefinition) }
    }

    /// Canonical in-house shortcut definition for Assistant.
    @Published public var assistantShortcutDefinition: ShortcutDefinition? {
        didSet { save(assistantShortcutDefinition, forKey: Keys.assistantShortcutDefinition) }
    }

    /// Canonical in-house shortcut definition for Meetings.
    @Published public var meetingShortcutDefinition: ShortcutDefinition? {
        didSet { save(meetingShortcutDefinition, forKey: Keys.meetingShortcutDefinition) }
    }

    /// Global shortcut definition used to cancel active recordings/captures.
    @Published public var cancelRecordingShortcutDefinition: ShortcutDefinition? {
        didSet { save(cancelRecordingShortcutDefinition, forKey: Keys.cancelRecordingShortcutDefinition) }
    }

    /// Modifier-only shortcut gesture for Dictation.
    @Published public var dictationModifierShortcutGesture: ModifierShortcutGesture? {
        didSet { save(dictationModifierShortcutGesture, forKey: Keys.dictationModifierShortcutGesture) }
    }

    /// Modifier-only shortcut gesture for Assistant.
    @Published public var assistantModifierShortcutGesture: ModifierShortcutGesture? {
        didSet { save(assistantModifierShortcutGesture, forKey: Keys.assistantModifierShortcutGesture) }
    }

    /// Modifier-only shortcut gesture for Meetings.
    @Published public var meetingModifierShortcutGesture: ModifierShortcutGesture? {
        didSet { save(meetingModifierShortcutGesture, forKey: Keys.meetingModifierShortcutGesture) }
    }

    /// How keyboard shortcuts activate Assistant commands.
    @Published public var assistantShortcutActivationMode: ShortcutActivationMode {
        didSet {
            UserDefaults.standard.set(
                assistantShortcutActivationMode.rawValue,
                forKey: Keys.assistantShortcutActivationMode,
            )
        }
    }

    /// Whether pressing Escape cancels Assistant recording.
    @Published public var assistantUseEscapeToCancelRecording: Bool {
        didSet { UserDefaults.standard.set(assistantUseEscapeToCancelRecording, forKey: Keys.assistantUseEscapeToCancelRecording) }
    }

    /// Whether pressing Enter stops Assistant recording and starts post-processing.
    @Published public var assistantUseEnterToStopRecording: Bool {
        didSet { UserDefaults.standard.set(assistantUseEnterToStopRecording, forKey: Keys.assistantUseEnterToStopRecording) }
    }

    /// Selected preset shortcut key for Assistant activation.
    @Published public var assistantSelectedPresetKey: PresetShortcutKey {
        didSet { UserDefaults.standard.set(assistantSelectedPresetKey.rawValue, forKey: Keys.assistantSelectedPresetKey) }
    }

    /// Color for the Assistant mode screen border.
    @Published public var assistantBorderColor: AssistantBorderColor {
        didSet { UserDefaults.standard.set(assistantBorderColor.rawValue, forKey: Keys.assistantBorderColor) }
    }

    /// Style for the Assistant mode screen border (stroke or glow).
    @Published public var assistantBorderStyle: AssistantBorderStyle {
        didSet { UserDefaults.standard.set(assistantBorderStyle.rawValue, forKey: Keys.assistantBorderStyle) }
    }

    /// Width for the Assistant mode screen border.
    @Published public var assistantBorderWidth: Double {
        didSet { UserDefaults.standard.set(assistantBorderWidth, forKey: Keys.assistantBorderWidth) }
    }

    /// Size for the Assistant mode glow effect.
    @Published public var assistantGlowSize: Double {
        didSet { UserDefaults.standard.set(assistantGlowSize, forKey: Keys.assistantGlowSize) }
    }

    /// Configured Assistant integrations (Raycast is pre-seeded by default).
    @Published public var assistantIntegrations: [AssistantIntegrationConfig] {
        didSet {
            guard !isSynchronizingAssistantIntegrations else { return }
            synchronizeAssistantIntegrationsState()
            save(assistantIntegrations, forKey: Keys.assistantIntegrations)
        }
    }

    /// Currently selected Assistant integration.
    @Published public var assistantSelectedIntegrationId: UUID? {
        didSet {
            if let id = assistantSelectedIntegrationId {
                UserDefaults.standard.set(id.uuidString, forKey: Keys.assistantSelectedIntegrationId)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.assistantSelectedIntegrationId)
            }
        }
    }

    /// Whether Raycast integration is enabled for Assistant mode.
    @Published public var assistantRaycastEnabled: Bool {
        didSet { UserDefaults.standard.set(assistantRaycastEnabled, forKey: Keys.assistantRaycastEnabled) }
    }

    /// Base deeplink used for Raycast AI command integration.
    @Published public var assistantRaycastDeepLink: String {
        didSet { UserDefaults.standard.set(assistantRaycastDeepLink, forKey: Keys.assistantRaycastDeepLink) }
    }

    /// When enabled, the app will auto-detect the meeting type for new meetings.
    /// When disabled, it will use the selected meeting prompt as the baseline.
    @Published public var meetingTypeAutoDetectEnabled: Bool {
        didSet { UserDefaults.standard.set(meetingTypeAutoDetectEnabled, forKey: Keys.meetingTypeAutoDetectEnabled) }
    }

    /// Preferred output language for meeting summaries.
    @Published public var meetingSummaryOutputLanguage: DictationOutputLanguage {
        didSet { UserDefaults.standard.set(meetingSummaryOutputLanguage.rawValue, forKey: Keys.meetingSummaryOutputLanguage) }
    }

    /// Path URL for exporting summaries.
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

    /// Markdown template for summary generation.
    @Published public var summaryTemplate: String {
        didSet { UserDefaults.standard.set(summaryTemplate, forKey: Keys.summaryTemplate) }
    }

    /// Whether summary template formatting is applied to exported files.
    @Published public var summaryTemplateEnabled: Bool {
        didSet { UserDefaults.standard.set(summaryTemplateEnabled, forKey: Keys.summaryTemplateEnabled) }
    }

    /// Whether to automatically export summaries after generation.
    @Published public var autoExportSummaries: Bool {
        didSet { UserDefaults.standard.set(autoExportSummaries, forKey: Keys.autoExportSummaries) }
    }

    /// Export safety policy level used to validate and sanitize summary exports.
    @Published public var summaryExportSafetyPolicyLevel: SummaryExportSafetyPolicyLevel {
        didSet { UserDefaults.standard.set(summaryExportSafetyPolicyLevel.rawValue, forKey: Keys.summaryExportSafetyPolicyLevel) }
    }

    /// Enables the global hotkey that summons the meeting notes pane.
    @Published public var meetingNotesHotkeyEnabled: Bool {
        didSet { UserDefaults.standard.set(meetingNotesHotkeyEnabled, forKey: Keys.meetingNotesHotkeyEnabled) }
    }

    /// In-house shortcut definition for the meeting notes pane hotkey.
    @Published public var meetingNotesShortcutDefinition: ShortcutDefinition? {
        didSet {
            if let meetingNotesShortcutDefinition {
                save(meetingNotesShortcutDefinition, forKey: Keys.meetingNotesShortcutDefinition)
            } else if let data = try? JSONEncoder().encode(ShortcutDefinition?.none) {
                // Persist explicit null so relaunch keeps "cleared" instead of restoring the default.
                UserDefaults.standard.set(data, forKey: Keys.meetingNotesShortcutDefinition)
            }
        }
    }

    /// Uses translucent material for the floating notes pane.
    @Published public var meetingNotesTranslucentPanel: Bool {
        didSet { UserDefaults.standard.set(meetingNotesTranslucentPanel, forKey: Keys.meetingNotesTranslucentPanel) }
    }

    /// Shows the notes pane on all Spaces and over full-screen apps.
    @Published public var meetingNotesShowOnAllSpaces: Bool {
        didSet { UserDefaults.standard.set(meetingNotesShowOnAllSpaces, forKey: Keys.meetingNotesShowOnAllSpaces) }
    }

    /// Hides the notes pane from screen capture and sharing.
    @Published public var meetingNotesHideFromScreenCapture: Bool {
        didSet { UserDefaults.standard.set(meetingNotesHideFromScreenCapture, forKey: Keys.meetingNotesHideFromScreenCapture) }
    }

    /// Automatically resizes pane height to fit note content.
    @Published public var meetingNotesAutoSizeHeight: Bool {
        didSet { UserDefaults.standard.set(meetingNotesAutoSizeHeight, forKey: Keys.meetingNotesAutoSizeHeight) }
    }

    /// Optional CSS theme name for the web notes editor.
    @Published public var meetingNotesEditorTheme: String {
        didSet { UserDefaults.standard.set(meetingNotesEditorTheme, forKey: Keys.meetingNotesEditorTheme) }
    }

    /// Base text size passed to the web notes editor.
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

    /// Last calendar event whose notes were edited; used for idle summon scope.
    @Published public var meetingNotesLastEditedCalendarEventIdentifier: String? {
        didSet {
            if let meetingNotesLastEditedCalendarEventIdentifier {
                UserDefaults.standard.set(
                    meetingNotesLastEditedCalendarEventIdentifier,
                    forKey: Keys.meetingNotesLastEditedCalendarEventIdentifier,
                )
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.meetingNotesLastEditedCalendarEventIdentifier)
            }
        }
    }

    /// Enables grounded single-turn Q&A in transcription detail.
    @Published public var meetingQnAEnabled: Bool {
        didSet { UserDefaults.standard.set(meetingQnAEnabled, forKey: Keys.meetingQnAEnabled) }
    }

    /// Master switch for proactive meeting reminders (lead notification + overlay).
    @Published public var meetingRemindersEnabled: Bool {
        didSet { UserDefaults.standard.set(meetingRemindersEnabled, forKey: Keys.meetingRemindersEnabled) }
    }

    /// Minutes before meeting start to deliver a lead-time notification (0 = off).
    @Published public var meetingReminderLeadMinutes: Int {
        didSet { UserDefaults.standard.set(meetingReminderLeadMinutes, forKey: Keys.meetingReminderLeadMinutes) }
    }

    /// Seconds before meeting start to fire the full-screen overlay.
    @Published public var meetingReminderOverlayLeadSeconds: Int {
        didSet { UserDefaults.standard.set(meetingReminderOverlayLeadSeconds, forKey: Keys.meetingReminderOverlayLeadSeconds) }
    }

    /// Whether the full-screen overlay is shown at meeting start.
    @Published public var meetingReminderOverlayEnabled: Bool {
        didSet { UserDefaults.standard.set(meetingReminderOverlayEnabled, forKey: Keys.meetingReminderOverlayEnabled) }
    }

    /// Plays the system alert sound when the overlay appears.
    @Published public var meetingReminderAlertSoundEnabled: Bool {
        didSet { UserDefaults.standard.set(meetingReminderAlertSoundEnabled, forKey: Keys.meetingReminderAlertSoundEnabled) }
    }

    /// Mirrors the overlay on every connected display.
    @Published public var meetingReminderMirrorAllScreens: Bool {
        didSet { UserDefaults.standard.set(meetingReminderMirrorAllScreens, forKey: Keys.meetingReminderMirrorAllScreens) }
    }

    /// Enables Context Awareness to enrich AI post-processing with active app context.
    @Published public var contextAwarenessEnabled: Bool {
        didSet {
            UserDefaults.standard.set(contextAwarenessEnabled, forKey: Keys.contextAwarenessEnabled)
            if contextAwarenessEnabled {
                contextAwarenessIncludeAccessibilityText = true
            }
        }
    }

    /// Includes clipboard text in context metadata.
    @Published public var contextAwarenessIncludeClipboard: Bool {
        didSet { UserDefaults.standard.set(contextAwarenessIncludeClipboard, forKey: Keys.contextAwarenessIncludeClipboard) }
    }

    /// Includes OCR text extracted from the active window image.
    @Published public var contextAwarenessIncludeWindowOCR: Bool {
        didSet { UserDefaults.standard.set(contextAwarenessIncludeWindowOCR, forKey: Keys.contextAwarenessIncludeWindowOCR) }
    }

    /// Includes focused UI text extracted via macOS Accessibility APIs.
    @Published public var contextAwarenessIncludeAccessibilityText: Bool {
        didSet { UserDefaults.standard.set(contextAwarenessIncludeAccessibilityText, forKey: Keys.contextAwarenessIncludeAccessibilityText) }
    }

    /// Redacts sensitive patterns (email, URLs, tokens, long numeric sequences) before sending context to AI.
    @Published public var contextAwarenessRedactSensitiveData: Bool {
        didSet { UserDefaults.standard.set(contextAwarenessRedactSensitiveData, forKey: Keys.contextAwarenessRedactSensitiveData) }
    }

    /// Additional app bundle identifiers excluded from context capture.
    @Published public var contextAwarenessExcludedBundleIDs: [String] {
        didSet { save(contextAwarenessExcludedBundleIDs, forKey: Keys.contextAwarenessExcludedBundleIDs) }
    }

    /// Bundle identifiers that should force Markdown formatting for dictation.
    @Published public var markdownTargetBundleIdentifiers: [String] {
        didSet { save(markdownTargetBundleIdentifiers, forKey: Keys.markdownTargetBundleIdentifiers) }
    }

    /// Per-app dictation overrides (Markdown and output language).
    @Published public var dictationAppRules: [DictationAppRule] {
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
                legacyBrowsers: webTargetBrowserBundleIdentifiers,
            )

            if synchronizedBrowsers != webTargetBrowserBundleIdentifiers {
                webTargetBrowserBundleIdentifiers = synchronizedBrowsers
            }
        }
    }

    /// Style-based dictation overrides for prompt, formatting, and language behavior.
    @Published public var dictationStyles: [DictationStyle] {
        didSet {
            let normalizedStyles = Self.normalizedDictationStyles(
                dictationStyles,
                defaultStyle: currentDefaultDictationStyle(),
            )
            if normalizedStyles != dictationStyles {
                dictationStyles = normalizedStyles
                return
            }

            save(dictationStyles, forKey: Keys.dictationStyles)
        }
    }

    /// Deterministic find-and-replace rules applied before post-processing.
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

    /// Vocabulary terms providing recognition/spelling hints for transcription.
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

    /// Website targets that should force Markdown formatting for dictation.
    @Published public var markdownWebTargets: [WebContextTarget] {
        didSet { save(markdownWebTargets, forKey: Keys.markdownWebTargets) }
    }

    /// Browser bundle identifiers used for matching web targets.
    @Published public var webTargetBrowserBundleIdentifiers: [String] {
        didSet { save(webTargetBrowserBundleIdentifiers, forKey: Keys.webTargetBrowserBundleIdentifiers) }
    }

    /// Bundle identifiers monitored to auto-start/stop meetings.
    @Published public var monitoredMeetingBundleIdentifiers: [String] {
        didSet { save(monitoredMeetingBundleIdentifiers, forKey: Keys.monitoredMeetingBundleIdentifiers) }
    }

    /// Web meeting targets detected by URL matching in browsers.
    @Published public var webMeetingTargets: [WebMeetingTarget] {
        didSet { save(webMeetingTargets, forKey: Keys.webMeetingTargets) }
    }

    /// Whether the floating recording indicator is enabled.
    @Published public var recordingIndicatorEnabled: Bool {
        didSet { UserDefaults.standard.set(recordingIndicatorEnabled, forKey: Keys.recordingIndicatorEnabled) }
    }

    /// Style of the floating recording indicator.
    @Published public var recordingIndicatorStyle: RecordingIndicatorStyle {
        didSet { UserDefaults.standard.set(recordingIndicatorStyle.rawValue, forKey: Keys.recordingIndicatorStyle) }
    }

    /// Position of the floating recording indicator on screen.
    @Published public var recordingIndicatorPosition: RecordingIndicatorPosition {
        didSet { UserDefaults.standard.set(recordingIndicatorPosition.rawValue, forKey: Keys.recordingIndicatorPosition) }
    }

    /// Animation speed profile used by the floating recording indicator waveform bars.
    @Published public var recordingIndicatorAnimationSpeed: RecordingIndicatorAnimationSpeed {
        didSet {
            UserDefaults.standard.set(
                recordingIndicatorAnimationSpeed.rawValue,
                forKey: Keys.recordingIndicatorAnimationSpeed,
            )
        }
    }

    /// Delay before automatic meeting recording starts after a meeting candidate is detected.
    @Published public var automaticAutomaticMeetingRecordingConfirmationDelay: AutomaticMeetingRecordingConfirmationDelay {
        didSet {
            UserDefaults.standard.set(
                automaticAutomaticMeetingRecordingConfirmationDelay.rawValue,
                forKey: Keys.automaticAutomaticMeetingRecordingConfirmationDelay,
            )
        }
    }

    /// Whether retention limit for old recordings on disk is enabled.
    @Published public var autoDeleteTranscriptions: Bool {
        didSet { UserDefaults.standard.set(autoDeleteTranscriptions, forKey: Keys.autoDeleteTranscriptions) }
    }

    /// Number of days to keep recordings on disk before cleanup.
    @Published public var autoDeletePeriodDays: Int {
        didSet { UserDefaults.standard.set(autoDeletePeriodDays, forKey: Keys.autoDeletePeriodDays) }
    }

    /// Primary accent color for the application.
    @Published public var appAccentColor: AppThemeColor {
        didSet { UserDefaults.standard.set(appAccentColor.rawValue, forKey: Keys.appAccentColor) }
    }

    /// Whether sound feedback for recording events is enabled.
    @Published public var soundFeedbackEnabled: Bool {
        didSet { UserDefaults.standard.set(soundFeedbackEnabled, forKey: Keys.soundFeedbackEnabled) }
    }

    /// Sound to play when recording starts.
    @Published public var recordingStartSound: SoundFeedbackSound {
        didSet { UserDefaults.standard.set(recordingStartSound.rawValue, forKey: Keys.recordingStartSound) }
    }

    /// Sound to play when recording stops.
    @Published public var recordingStopSound: SoundFeedbackSound {
        didSet { UserDefaults.standard.set(recordingStopSound.rawValue, forKey: Keys.recordingStopSound) }
    }

    /// Whether to show the app icon in the Dock (allows Cmd+Tab switching).
    @Published public var showInDock: Bool {
        didSet { UserDefaults.standard.set(showInDock, forKey: Keys.showInDock) }
    }

    /// Preferred appearance mode (light, dark, or system).
    @Published public var appearanceMode: AppearanceMode {
        didSet { UserDefaults.standard.set(appearanceMode.rawValue, forKey: Keys.appearanceMode) }
    }

    /// Whether the user has completed the onboarding flow.
    @Published public var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    // MARK: - Initialization

    // The public stored-property surface requires direct assignment after loading grouped values.
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
            capabilities.isAssistantIntegrationsEnabled,
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
            shortcuts.dictationShortcutActivationMode,
        )
        shortcutDoubleTapIntervalMilliseconds = shortcuts.shortcutDoubleTapIntervalMilliseconds
        useEscapeToCancelRecording = shortcuts.useEscapeToCancelRecording
        (selectedPresetKey, dictationSelectedPresetKey, meetingSelectedPresetKey) = (
            shortcuts.selectedPresetKey,
            shortcuts.dictationSelectedPresetKey,
            shortcuts.meetingSelectedPresetKey,
        )
        cancelRecordingShortcutDefinition = shortcuts.cancelRecordingShortcutDefinition

        let gestures = values.gestures
        (dictationModifierShortcutGesture, assistantModifierShortcutGesture, meetingModifierShortcutGesture) = (
            gestures.dictation,
            gestures.assistant,
            gestures.meeting,
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
            ctx.contextAwarenessIncludeWindowOCR,
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
        recordingIndicatorStyle = uiSettings.recordingIndicatorStyle
        recordingIndicatorPosition = uiSettings.recordingIndicatorPosition
        recordingIndicatorAnimationSpeed = uiSettings.recordingIndicatorAnimationSpeed
        automaticAutomaticMeetingRecordingConfirmationDelay = uiSettings.automaticAutomaticMeetingRecordingConfirmationDelay
        autoDeleteTranscriptions = uiSettings.autoDeleteTranscriptions
        autoDeletePeriodDays = uiSettings.autoDeletePeriodDays
        appAccentColor = uiSettings.appAccentColor
        appearanceMode = uiSettings.appearanceMode
        soundFeedbackEnabled = uiSettings.soundFeedbackEnabled
        recordingStartSound = uiSettings.recordingStartSound
        recordingStopSound = uiSettings.recordingStopSound
        showInDock = uiSettings.showInDock
        hasCompletedOnboarding = values.hasCompletedOnboarding

        finalizeInitialization(context: context)
    }
}

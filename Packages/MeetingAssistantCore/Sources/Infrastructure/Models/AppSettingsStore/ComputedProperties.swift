import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain

// MARK: - Computed Properties

public extension AppSettingsStore {
    func currentDefaultDictationStyle() -> DictationStyle {
        Self.defaultDictationStyle(
            contextAwarenessEnabled: contextAwarenessEnabled,
            includeClipboard: contextAwarenessIncludeClipboard,
            includeWindowOCR: contextAwarenessIncludeWindowOCR,
            includeAccessibilityText: contextAwarenessIncludeAccessibilityText,
            redactSensitiveData: contextAwarenessRedactSensitiveData,
            dictationSelection: enhancementsDictationAISelection,
            textHandlingPolicy: DictationTextHandlingPolicy(
                autoCopyToClipboard: autoCopyTranscriptionToClipboard,
                autoPasteToActiveApp: autoPasteTranscriptionToActiveApp,
                smartSpacingAndCapitalization: smartSpacingAndCapitalizationEnabled,
                smartParagraphs: smartParagraphsEnabled
            ),
            transcriptionConfiguration: DictationTranscriptionConfiguration(
                selection: resolvedTranscriptionSelection(for: .dictation),
                inputLanguageCode: resolvedTranscriptionInputLanguageCode(for: .dictation)
            )
        )
    }

    func effectiveDictationStyle(bundleIdentifier: String?, activeURL: URL?) -> DictationStyle {
        if let matchedStyle = dictationStyles.first(where: {
            !$0.isDefault && $0.matches(bundleIdentifier: bundleIdentifier, activeURL: activeURL)
        }) {
            return matchedStyle
        }

        return dictationStyles.first(where: \.isDefault) ?? currentDefaultDictationStyle()
    }

    /// Indicates whether the Markdown targets list has been explicitly configured.
    var hasConfiguredMarkdownTargets: Bool {
        UserDefaults.standard.object(forKey: Keys.markdownTargetBundleIdentifiers) != nil
    }

    /// Indicates whether the per-app dictation rules list has been explicitly configured.
    var hasConfiguredDictationAppRules: Bool {
        UserDefaults.standard.object(forKey: Keys.dictationAppRules) != nil
    }

    /// Indicates whether dictation styles have been explicitly configured.
    var hasConfiguredDictationStyles: Bool {
        UserDefaults.standard.object(forKey: Keys.dictationStyles) != nil
    }

    /// Indicates whether Markdown web targets have been explicitly configured.
    var hasConfiguredMarkdownWebTargets: Bool {
        UserDefaults.standard.object(forKey: Keys.markdownWebTargets) != nil
    }

    /// Indicates whether the global web target browsers list has been explicitly configured.
    var hasConfiguredWebTargetBrowsers: Bool {
        UserDefaults.standard.object(forKey: Keys.webTargetBrowserBundleIdentifiers) != nil
    }

    /// Indicates whether the monitored meetings list has been explicitly configured.
    var hasConfiguredMonitoredMeetingApps: Bool {
        UserDefaults.standard.object(forKey: Keys.monitoredMeetingBundleIdentifiers) != nil
    }

    /// Indicates whether web meeting targets have been explicitly configured.
    var hasConfiguredWebMeetingTargets: Bool {
        UserDefaults.standard.object(forKey: Keys.webMeetingTargets) != nil
    }

    /// All available prompts (predefined + user-created), filtered by deleted and overrides.
    var allPrompts: [PostProcessingPrompt] {
        deduplicatedPrompts(dictationAvailablePrompts + meetingAvailablePrompts)
    }

    /// Dictation prompts (predefined + user-created).
    var dictationAvailablePrompts: [PostProcessingPrompt] {
        let predefined: [PostProcessingPrompt] = [
            .defaultPrompt,
            .flex
        ]
        let predefinedIds = Set(predefined.map(\.id))
        let custom = dictationPrompts + userPrompts.filter { predefinedIds.contains($0.id) }
        return mergedPrompts(predefined: predefined, custom: custom)
    }

    /// Meeting prompts (predefined + user-created).
    var meetingAvailablePrompts: [PostProcessingPrompt] {
        let predefined: [PostProcessingPrompt] = [
            .standup,
            .presentation,
            .designReview,
            .oneOnOne,
            .planning
        ]

        // Backward-compat: prompts created in older versions lived under `userPrompts`.
        // Clean Transcription is dictation-only, so keep it out of meeting prompts.
        let custom = (meetingPrompts + userPrompts)
            .filter { $0.id != PostProcessingPrompt.cleanTranscription.id }
        return mergedPrompts(predefined: predefined, custom: custom)
    }

    /// Currently selected prompt.
    var selectedPrompt: PostProcessingPrompt? {
        guard let id = selectedPromptId, id != Self.noPostProcessingPromptId else { return nil }
        return meetingAvailablePrompts.first { $0.id == id }
    }

    /// Currently selected dictation prompt.
    var selectedDictationPrompt: PostProcessingPrompt? {
        guard let id = dictationSelectedPromptId, id != Self.noPostProcessingPromptId else { return nil }
        return dictationAvailablePrompts.first { $0.id == id }
    }

    var isMeetingPostProcessingDisabled: Bool {
        selectedPromptId == Self.noPostProcessingPromptId
    }

    var isDictationPostProcessingDisabled: Bool {
        dictationSelectedPromptId == Self.noPostProcessingPromptId
    }

    /// Browser bundle identifiers currently in effect for web target matching.
    var effectiveWebTargetBrowserBundleIdentifiers: [String] {
        synchronizedWebTargetBrowsers(
            from: dictationAppRules,
            legacyBrowsers: webTargetBrowserBundleIdentifiers
        )
    }

    /// Whether the shared intelligence kernel is globally enabled.
    var intelligenceKernelEnabled: Bool {
        FeatureFlags.enableIntelligenceKernel
    }

    /// Returns whether a specific intelligence-kernel mode is enabled.
    func isIntelligenceKernelModeEnabled(_ mode: IntelligenceKernelMode) -> Bool {
        guard intelligenceKernelEnabled else { return false }

        switch mode {
        case .meeting:
            return FeatureFlags.enableMeetingIntelligenceMode
        case .dictation:
            return FeatureFlags.enableDictationIntelligenceMode
        case .assistant:
            return FeatureFlags.enableAssistantIntelligenceMode
        }
    }
}

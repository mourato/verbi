import Foundation
import VerbiCoreCommon
import VerbiCoreDomain

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

    var hasConfiguredMarkdownTargets: Bool {
        UserDefaults.standard.object(forKey: Keys.markdownTargetBundleIdentifiers) != nil
    }

    var hasConfiguredDictationAppRules: Bool {
        UserDefaults.standard.object(forKey: Keys.dictationAppRules) != nil
    }

    var hasConfiguredDictationStyles: Bool {
        UserDefaults.standard.object(forKey: Keys.dictationStyles) != nil
    }

    var hasConfiguredMarkdownWebTargets: Bool {
        UserDefaults.standard.object(forKey: Keys.markdownWebTargets) != nil
    }

    var hasConfiguredWebTargetBrowsers: Bool {
        UserDefaults.standard.object(forKey: Keys.webTargetBrowserBundleIdentifiers) != nil
    }

    var hasConfiguredMonitoredMeetingApps: Bool {
        UserDefaults.standard.object(forKey: Keys.monitoredMeetingBundleIdentifiers) != nil
    }

    var hasConfiguredWebMeetingTargets: Bool {
        UserDefaults.standard.object(forKey: Keys.webMeetingTargets) != nil
    }

    var allPrompts: [PostProcessingPrompt] {
        deduplicatedPrompts(dictationAvailablePrompts + meetingAvailablePrompts)
    }

    var dictationAvailablePrompts: [PostProcessingPrompt] {
        let predefined: [PostProcessingPrompt] = [
            .defaultPrompt,
            .flex
        ]
        let predefinedIds = Set(predefined.map(\.id))
        let custom = dictationPrompts + userPrompts.filter { predefinedIds.contains($0.id) }
        return mergedPrompts(predefined: predefined, custom: custom)
    }

    var meetingAvailablePrompts: [PostProcessingPrompt] {
        let predefined: [PostProcessingPrompt] = [
            .standup,
            .presentation,
            .designReview,
            .oneOnOne,
            .planning
        ]

        let custom = (meetingPrompts + userPrompts)
            .filter { $0.id != PostProcessingPrompt.cleanTranscription.id }
        return mergedPrompts(predefined: predefined, custom: custom)
    }

    var selectedPrompt: PostProcessingPrompt? {
        guard let id = selectedPromptId, id != Self.noPostProcessingPromptId else { return nil }
        return meetingAvailablePrompts.first { $0.id == id }
    }

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

    var effectiveWebTargetBrowserBundleIdentifiers: [String] {
        synchronizedWebTargetBrowsers(
            from: dictationAppRules,
            legacyBrowsers: webTargetBrowserBundleIdentifiers
        )
    }

    var intelligenceKernelEnabled: Bool {
        FeatureFlags.enableIntelligenceKernel
    }

    func isIntelligenceKernelModeEnabled(_ mode: CaptureMode) -> Bool {
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

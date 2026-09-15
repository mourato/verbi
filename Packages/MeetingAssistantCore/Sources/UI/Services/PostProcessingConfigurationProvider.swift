import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

public struct DictationContextSnapshot {
    public let bundleIdentifier: String?
    public let activeURL: URL?
    public let outputLanguageOverride: DictationOutputLanguage?
    public let style: DictationStyle?

    public init(
        bundleIdentifier: String?,
        activeURL: URL?,
        outputLanguageOverride: DictationOutputLanguage?,
        style: DictationStyle? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.activeURL = activeURL
        self.outputLanguageOverride = outputLanguageOverride
        self.style = style
    }
}

@MainActor
public final class PostProcessingConfigurationProvider {
    private let apiKeyExists: (AIProvider) -> Bool

    public init(apiKeyExists: @escaping (AIProvider) -> Bool) {
        self.apiKeyExists = apiKeyExists
    }

    public func shouldApplyEnhancementsPostProcessing(
        settings: AppSettingsStore,
        kernelMode: IntelligenceKernelMode
    ) -> Bool {
        let readinessIssue = settings.enhancementsInferenceReadinessIssue(for: kernelMode, apiKeyExists: apiKeyExists)
        let kernelModeEnabled = settings.isIntelligenceKernelModeEnabled(kernelMode)

        return settings.postProcessingEnabled
            && readinessIssue == nil
            && kernelModeEnabled
    }

    public func makeAvailablePrompts(
        isDictation: Bool,
        settings: AppSettingsStore
    ) -> [DomainPostProcessingPrompt] {
        guard !isDictation else { return [] }

        let builtIn: [PostProcessingPrompt] = [.standup, .presentation, .designReview, .oneOnOne, .planning]
        return (builtIn + settings.meetingPrompts).map(domainPrompt(from:))
    }

    public func makeDefaultMeetingPrompt(
        isDictation: Bool,
        settings: AppSettingsStore
    ) -> DomainPostProcessingPrompt? {
        guard !isDictation else { return nil }

        if let selected = settings.selectedPrompt {
            return domainPrompt(from: selected)
        }

        return domainPrompt(from: PromptService.shared.strategy(for: .general).promptObject())
    }

    public func resolvePostProcessingPromptForUseCase(
        meeting: Meeting,
        isDictation: Bool,
        settings: AppSettingsStore,
        defaultMeetingPrompt: DomainPostProcessingPrompt?,
        dictationContext: DictationContextSnapshot
    ) -> DomainPostProcessingPrompt? {
        if isDictation {
            let basePrompt = settings.selectedDictationPrompt ?? .defaultPrompt
            let resolvedPrompt = promptWithDictationRuleOverrides(
                prompt: basePrompt,
                settings: settings,
                dictationContext: dictationContext
            )
            return domainPrompt(from: resolvedPrompt)
        }

        switch meeting.type {
        case .autodetect:
            return nil
        case .standup:
            return domainPrompt(from: promptWithMeetingSummaryOverrides(prompt: .standup))
        case .presentation:
            return domainPrompt(from: promptWithMeetingSummaryOverrides(prompt: .presentation))
        case .designReview:
            return domainPrompt(from: promptWithMeetingSummaryOverrides(prompt: .designReview))
        case .oneOnOne:
            return domainPrompt(from: promptWithMeetingSummaryOverrides(prompt: .oneOnOne))
        case .planning:
            return domainPrompt(from: promptWithMeetingSummaryOverrides(prompt: .planning))
        case .general:
            guard let defaultMeetingPrompt else { return nil }
            let prompt = PostProcessingPrompt(
                id: defaultMeetingPrompt.id,
                title: defaultMeetingPrompt.title,
                promptText: defaultMeetingPrompt.content,
                isPredefined: false
            )
            let enrichedPrompt = promptWithMeetingSummaryOverrides(prompt: prompt)
            return domainPrompt(from: enrichedPrompt)
        }
    }

    public func domainPrompt(from prompt: PostProcessingPrompt) -> DomainPostProcessingPrompt {
        DomainPostProcessingPrompt(id: prompt.id, title: prompt.title, content: prompt.promptText, isDefault: false)
    }

    public func promptWithDictationRuleOverrides(
        prompt: PostProcessingPrompt,
        settings: AppSettingsStore,
        dictationContext: DictationContextSnapshot
    ) -> PostProcessingPrompt {
        let matchedStyle = matchingDictationStyleForDictation(settings: settings, dictationContext: dictationContext)
        let basePromptText = resolvedDictationBasePromptText(
            defaultPromptText: prompt.promptText,
            matchedStyle: matchedStyle
        )

        var appliedInstructions: [String] = []
        var priorityInstructions: [String] = []

        if shouldForceMarkdownForDictation(settings: settings, dictationContext: dictationContext, matchedStyle: matchedStyle) {
            appliedInstructions.append(Self.markdownFormatInstruction)
        }

        let outputLanguage = outputLanguageForDictation(
            settings: settings,
            dictationContext: dictationContext,
            matchedStyle: matchedStyle
        )
        if outputLanguage != .original {
            priorityInstructions.append(Self.translationInstruction(for: outputLanguage))
        }

        if let customInstructions = effectiveCustomPromptInstructionsForDictation(
            settings: settings,
            dictationContext: dictationContext,
            matchedStyle: matchedStyle
        ) {
            priorityInstructions.append(customInstructions)
        }

        if !priorityInstructions.isEmpty {
            appliedInstructions.append(
                Self.siteOrAppPriorityInstructionBlock(priorityInstructions.joined(separator: "\n\n"))
            )
        }

        guard !(appliedInstructions.isEmpty && basePromptText == prompt.promptText) else { return prompt }

        let augmentedText = ([basePromptText] + appliedInstructions).joined(separator: "\n\n")

        return PostProcessingPrompt(
            id: prompt.id,
            title: prompt.title,
            promptText: augmentedText,
            isActive: prompt.isActive,
            icon: prompt.icon,
            description: prompt.description,
            isPredefined: prompt.isPredefined
        )
    }

    public func matchingDictationStyleForDictation(
        settings: AppSettingsStore,
        dictationContext: DictationContextSnapshot
    ) -> DictationStyle? {
        if let style = dictationContext.style {
            return style
        }
        return settings.effectiveDictationStyle(
            bundleIdentifier: dictationContext.bundleIdentifier,
            activeURL: dictationContext.activeURL
        )
    }

    public func effectiveCustomPromptInstructionsForDictation(
        settings: AppSettingsStore,
        dictationContext: DictationContextSnapshot,
        matchedStyle: DictationStyle? = nil
    ) -> String? {
        guard let style = matchedStyle ?? matchingDictationStyleForDictation(settings: settings, dictationContext: dictationContext) else {
            return nil
        }

        guard !style.replaceBasePrompt else { return nil }

        let normalized = style.promptInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    public func matchingDictationAppRule(
        settings: AppSettingsStore,
        dictationContext: DictationContextSnapshot
    ) -> DictationAppRule? {
        guard let bundleIdentifier = dictationContext.bundleIdentifier else { return nil }
        let normalized = WebTargetDetection.normalizeBundleIdentifier(bundleIdentifier)

        return settings.dictationAppRules.first {
            WebTargetDetection.normalizeBundleIdentifier($0.bundleIdentifier) == normalized
        }
    }

    public func outputLanguageForDictation(
        settings: AppSettingsStore,
        dictationContext: DictationContextSnapshot,
        matchedStyle: DictationStyle? = nil
    ) -> DictationOutputLanguage {
        if let override = dictationContext.outputLanguageOverride {
            return override
        }

        return (matchedStyle ?? matchingDictationStyleForDictation(settings: settings, dictationContext: dictationContext))?.outputLanguage ?? .original
    }

    public func shouldForceMarkdownForDictation(
        settings: AppSettingsStore,
        dictationContext: DictationContextSnapshot,
        matchedStyle: DictationStyle? = nil
    ) -> Bool {
        (matchedStyle ?? matchingDictationStyleForDictation(settings: settings, dictationContext: dictationContext))?.forceMarkdownOutput ?? false
    }

    public func matchingWebContextTargetForDictation(
        settings: AppSettingsStore,
        dictationContext: DictationContextSnapshot
    ) -> WebContextTarget? {
        guard let bundleIdentifier = dictationContext.bundleIdentifier else { return nil }
        let normalized = WebTargetDetection.normalizeBundleIdentifier(bundleIdentifier)
        let webTargets = settings.markdownWebTargets
        guard !webTargets.isEmpty else { return nil }

        if let url = dictationContext.activeURL,
           let target = WebTargetDetection.matchTarget(
               for: url,
               bundleIdentifier: normalized,
               targets: webTargets,
               fallbackBrowserBundleIdentifiers: settings.effectiveWebTargetBrowserBundleIdentifiers
           )
        {
            return target
        }

        return WebTargetDetection.matchTargetByWindowTitle(
            bundleIdentifier: normalized,
            targets: webTargets,
            fallbackBrowserBundleIdentifiers: settings.effectiveWebTargetBrowserBundleIdentifiers
        )
    }

    public func promptWithMeetingSummaryOverrides(
        prompt: PostProcessingPrompt
    ) -> PostProcessingPrompt {
        let augmentedText = [
            prompt.promptText,
            Self.meetingNotesPriorityInstruction
        ].joined(separator: "\n\n")

        return PostProcessingPrompt(
            id: prompt.id,
            title: prompt.title,
            promptText: augmentedText,
            isActive: prompt.isActive,
            icon: prompt.icon,
            description: prompt.description,
            isPredefined: prompt.isPredefined
        )
    }

    private func resolvedDictationBasePromptText(
        defaultPromptText: String,
        matchedStyle: DictationStyle?
    ) -> String {
        guard let matchedStyle, matchedStyle.replaceBasePrompt else {
            return defaultPromptText
        }

        let stylePrompt = matchedStyle.promptInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stylePrompt.isEmpty else { return defaultPromptText }
        return stylePrompt
    }

    public static let markdownFormatInstruction = """
    <OUTPUT_FORMAT>
    ALWAYS format the output as Markdown. When formatting using Markdown, use traditional formatting conventions for ordered or unordered lists, **bold**, *italics*, and headings as well.
    </OUTPUT_FORMAT>
    """

    public static func translationInstruction(for language: DictationOutputLanguage) -> String {
        """
        <OUTPUT_LANGUAGE>
        Translate the final output to \(language.instructionDisplayName). This requirement overrides any instruction that says to keep the original language.
        </OUTPUT_LANGUAGE>
        """
    }

    public static let meetingNotesPriorityInstruction = """
    <MEETING_NOTES_POLICY>
    If a <MEETING_NOTES> block is present, treat it as high-priority user-provided signal.
    Preserve those points in the summary and enrich them only with grounded details from the transcription.
    Never contradict explicit meeting notes unless the transcription clearly disproves them.
    </MEETING_NOTES_POLICY>
    """

    public static func siteOrAppPriorityInstructionBlock(_ instructions: String) -> String {
        """
        <\(AIPromptTemplates.siteOrAppPriorityTag)>
        \(instructions)
        </\(AIPromptTemplates.siteOrAppPriorityTag)>
        """
    }
}

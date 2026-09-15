import Foundation
import MeetingAssistantCoreDomain

@MainActor
extension AppSettingsStore {
    func migrateWebTargetBrowsersToGlobalSettingIfNeeded() {
        let legacyMarkdownBrowsers = markdownWebTargets.flatMap(\.browserBundleIdentifiers)
        let legacyMeetingBrowsers = webMeetingTargets.flatMap(\.browserBundleIdentifiers)
        let mergedBrowsers = deduplicatedNormalizedBundleIdentifiers(
            webTargetBrowserBundleIdentifiers + legacyMarkdownBrowsers + legacyMeetingBrowsers
        )

        if mergedBrowsers != webTargetBrowserBundleIdentifiers {
            webTargetBrowserBundleIdentifiers = mergedBrowsers
        }

        let migratedMarkdownTargets = markdownWebTargets.map { target in
            WebContextTarget(
                id: target.id,
                displayName: target.displayName,
                urlPatterns: target.urlPatterns,
                browserBundleIdentifiers: [],
                forceMarkdownOutput: target.forceMarkdownOutput,
                outputLanguage: target.outputLanguage,
                autoStartMeetingRecording: target.autoStartMeetingRecording
            )
        }

        if migratedMarkdownTargets != markdownWebTargets {
            markdownWebTargets = migratedMarkdownTargets
        }

        let migratedMeetingTargets = webMeetingTargets.map { target in
            WebMeetingTarget(
                id: target.id,
                app: target.app,
                displayName: target.displayName,
                urlPatterns: target.urlPatterns,
                browserBundleIdentifiers: []
            )
        }

        if migratedMeetingTargets != webMeetingTargets {
            webMeetingTargets = migratedMeetingTargets
        }
    }

    func migrateLegacyMarkdownTargetsToDictationAppRulesIfNeeded() {
        guard !hasConfiguredDictationAppRules else { return }

        let migratedRules = Self.normalizedDictationAppRules(
            markdownTargetBundleIdentifiers.map {
                DictationAppRule(bundleIdentifier: $0, forceMarkdownOutput: true, outputLanguage: .original)
            }
        )

        dictationAppRules = migratedRules.isEmpty ? Self.defaultDictationAppRules : migratedRules
    }

    func migrateLegacyWebTargetBrowsersToDictationAppRulesIfNeeded() {
        let browserRules = webTargetBrowserBundleIdentifiers.map {
            DictationAppRule(bundleIdentifier: $0, forceMarkdownOutput: false, outputLanguage: .original)
        }

        let migratedRules = Self.normalizedDictationAppRules(dictationAppRules + browserRules)
        if migratedRules != dictationAppRules {
            dictationAppRules = migratedRules
        }

        let synchronizedBrowsers = synchronizedWebTargetBrowsers(
            from: dictationAppRules,
            legacyBrowsers: webTargetBrowserBundleIdentifiers
        )

        if synchronizedBrowsers != webTargetBrowserBundleIdentifiers {
            webTargetBrowserBundleIdentifiers = synchronizedBrowsers
        }
    }

    static func normalizedDictationAppRules(_ rules: [DictationAppRule]) -> [DictationAppRule] {
        var seenBundleIdentifiers = Set<String>()
        var ordered: [DictationAppRule] = []

        for rule in rules {
            let trimmedBundleIdentifier = rule.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedBundleIdentifier = trimmedBundleIdentifier.lowercased()

            guard !trimmedBundleIdentifier.isEmpty, !seenBundleIdentifiers.contains(normalizedBundleIdentifier) else {
                continue
            }

            seenBundleIdentifiers.insert(normalizedBundleIdentifier)
            ordered.append(
                DictationAppRule(
                    bundleIdentifier: trimmedBundleIdentifier,
                    forceMarkdownOutput: rule.forceMarkdownOutput,
                    outputLanguage: rule.outputLanguage,
                    customPromptInstructions: rule.customPromptInstructions
                )
            )
        }

        return ordered
    }

    static func defaultDictationStyle(
        contextAwarenessEnabled: Bool,
        includeClipboard: Bool,
        includeWindowOCR: Bool,
        includeAccessibilityText: Bool,
        redactSensitiveData: Bool,
        dictationSelection: EnhancementsAISelection,
        textHandlingPolicy: DictationTextHandlingPolicy = .init(),
        transcriptionConfiguration: DictationTranscriptionConfiguration = .init()
    ) -> DictationStyle {
        DictationStyle(
            id: defaultDictationModeID,
            name: "settings.dictation.modes.default_name".localized,
            iconSymbol: "textformat",
            promptInstructions: "",
            postProcessingEnabled: true,
            forceMarkdownOutput: false,
            replaceBasePrompt: false,
            outputLanguage: .original,
            targets: [],
            contextSourcePolicy: DictationContextSourcePolicy(
                includeClipboard: contextAwarenessEnabled && includeClipboard,
                includeWindowOCR: contextAwarenessEnabled && includeWindowOCR,
                includeAccessibilityText: contextAwarenessEnabled && includeAccessibilityText,
                redactSensitiveData: redactSensitiveData
            ),
            enhancementsSelection: dictationSelection,
            isDefault: true,
            textHandlingPolicy: textHandlingPolicy,
            transcriptionConfiguration: transcriptionConfiguration
        )
    }

    static func normalizedDictationStyles(
        _ styles: [DictationStyle],
        defaultStyle: DictationStyle = defaultDictationStyles[0]
    ) -> [DictationStyle] {
        var seenStyleIDs = Set<UUID>()
        var globallyAssignedTargetKeys = Set<String>()
        var userStyles: [DictationStyle] = []
        var persistedDefaultStyle: DictationStyle?

        for style in styles {
            guard seenStyleIDs.insert(style.id).inserted else { continue }
            if style.isDefault || style.id == defaultDictationModeID {
                if persistedDefaultStyle == nil {
                    persistedDefaultStyle = style
                }
                continue
            }

            var seenStyleTargetKeys = Set<String>()
            var normalizedTargets: [DictationStyleTarget] = []

            for target in style.targets {
                guard let normalizedTarget = target.normalized() else { continue }
                let identity = normalizedTarget.normalizedIdentity

                guard !seenStyleTargetKeys.contains(identity), !globallyAssignedTargetKeys.contains(identity) else {
                    continue
                }

                seenStyleTargetKeys.insert(identity)
                globallyAssignedTargetKeys.insert(identity)
                normalizedTargets.append(normalizedTarget)
            }

            userStyles.append(
                DictationStyle(
                    id: style.id,
                    name: style.normalizedName,
                    iconSymbol: style.normalizedIconSymbol,
                    promptInstructions: style.normalizedPromptInstructions,
                    postProcessingEnabled: style.postProcessingEnabled,
                    forceMarkdownOutput: style.forceMarkdownOutput,
                    replaceBasePrompt: style.replaceBasePrompt,
                    outputLanguage: style.outputLanguage,
                    targets: normalizedTargets,
                    contextSourcePolicy: style.contextSourcePolicy,
                    enhancementsSelection: style.enhancementsSelection,
                    isDefault: false,
                    textHandlingPolicy: style.textHandlingPolicy,
                    transcriptionConfiguration: style.transcriptionConfiguration
                )
            )
        }

        let normalizedDefault = normalizedDefaultDictationStyle(
            persistedDefaultStyle,
            fallback: defaultStyle
        )
        return [normalizedDefault] + userStyles
    }

    private static func normalizedDefaultDictationStyle(
        _ style: DictationStyle?,
        fallback: DictationStyle
    ) -> DictationStyle {
        let source = style ?? fallback
        return DictationStyle(
            id: defaultDictationModeID,
            name: source.normalizedName.isEmpty ? fallback.name : source.normalizedName,
            iconSymbol: source.normalizedIconSymbol,
            promptInstructions: source.normalizedPromptInstructions,
            postProcessingEnabled: source.postProcessingEnabled,
            forceMarkdownOutput: source.forceMarkdownOutput,
            replaceBasePrompt: source.replaceBasePrompt,
            outputLanguage: source.outputLanguage,
            targets: [],
            contextSourcePolicy: source.contextSourcePolicy ?? fallback.contextSourcePolicy,
            enhancementsSelection: source.enhancementsSelection ?? fallback.enhancementsSelection,
            isDefault: true,
            textHandlingPolicy: source.textHandlingPolicy,
            transcriptionConfiguration: source.transcriptionConfiguration
        )
    }

    public static func migrateLegacyDictationStyles(
        _ styles: [DictationStyle],
        dictationSelection: EnhancementsAISelection,
        transcriptionSelection: TranscriptionProviderSelection,
        inputLanguageCode: String?,
        textHandlingPolicy: DictationTextHandlingPolicy
    ) -> [DictationStyle] {
        styles.map { style in
            guard style.configurationSchemaVersion < DictationStyle.currentConfigurationSchemaVersion else {
                return style
            }

            return DictationStyle(
                id: style.id,
                name: style.name,
                iconSymbol: style.iconSymbol,
                promptInstructions: style.promptInstructions,
                postProcessingEnabled: style.postProcessingEnabled,
                forceMarkdownOutput: style.forceMarkdownOutput,
                replaceBasePrompt: style.replaceBasePrompt,
                outputLanguage: style.outputLanguage,
                targets: style.targets,
                contextSourcePolicy: style.contextSourcePolicy,
                enhancementsSelection: style.enhancementsSelection ?? dictationSelection,
                isDefault: style.isDefault,
                textHandlingPolicy: textHandlingPolicy,
                transcriptionConfiguration: DictationTranscriptionConfiguration(
                    selection: transcriptionSelection,
                    inputLanguageCode: inputLanguageCode
                )
            )
        }
    }

    private func deduplicatedNormalizedBundleIdentifiers(_ identifiers: [String]) -> [String] {
        var seenKeys = Set<String>()
        var ordered: [String] = []

        for identifier in identifiers {
            // Trim whitespace but preserve original casing for storage.
            let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedKey = Self.normalizeBundleIdentifier(trimmed)

            guard !trimmed.isEmpty, !seenKeys.contains(normalizedKey) else { continue }
            seenKeys.insert(normalizedKey)
            ordered.append(trimmed)
        }

        return ordered
    }

    func synchronizedWebTargetBrowsers(
        from rules: [DictationAppRule],
        legacyBrowsers: [String]
    ) -> [String] {
        let legacy = deduplicatedNormalizedBundleIdentifiers(legacyBrowsers)
        let legacyNormalized = Set(legacy.map(Self.normalizeBundleIdentifier))

        let browsersFromRules = deduplicatedNormalizedBundleIdentifiers(
            rules
                .map(\.bundleIdentifier)
                .filter { bundleIdentifier in
                    let normalizedBundleIdentifier = Self.normalizeBundleIdentifier(bundleIdentifier)
                    return BrowserProviderRegistry.isLikelyBrowserBundleIdentifier(normalizedBundleIdentifier)
                        || legacyNormalized.contains(normalizedBundleIdentifier)
                }
        )

        return browsersFromRules.isEmpty ? legacy : browsersFromRules
    }

    private nonisolated static func normalizeBundleIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

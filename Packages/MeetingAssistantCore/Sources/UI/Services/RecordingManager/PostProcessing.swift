import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

// MARK: - Post Processing Configuration

extension RecordingManager {
    struct UseCaseConfig {
        let kernelMode: IntelligenceKernelMode
        let applyPostProcessing: Bool
        let dictationStructuredPostProcessingEnabled: Bool
        var postProcessingPrompt: DomainPostProcessingPrompt?
        var defaultPostProcessingPrompt: DomainPostProcessingPrompt?
        let postProcessingModel: String?
        let postProcessingIdentity: ModelPerformanceModelIdentity?
        let postProcessingConfiguration: DomainPostProcessingConfiguration?
        let postProcessingFailureReason: String?
        var autoDetectMeetingType: Bool
        let availablePrompts: [DomainPostProcessingPrompt]
        var postProcessingContext: String?
        let postProcessingSystemPrompt: String?
        var postProcessingContextItems: [TranscriptionContextItem]
        let dictationTextHandlingPolicy: DictationTextHandlingPolicy?
        let dictationTranscriptionConfiguration: DictationTranscriptionConfiguration?
        let postProcessingSelection: EnhancementsAISelection?
    }

    // swiftlint:disable:next function_body_length
    func makeUseCaseConfig(
        session: TranscriptionSessionSnapshot,
        settings: AppSettingsStore
    ) -> UseCaseConfig {
        let meeting = session.meeting
        let kernelMode = session.kernelMode
        let isDictation = kernelMode == .dictation
        let postProcessingSelection = resolvedPostProcessingSelection(session: session, settings: settings)
        let modePostProcessingEnabled = dictationPostProcessingEnabled(for: session, settings: settings)
        let readinessIssue = modePostProcessingEnabled
            ? (isDictation
                ? settings.enhancementsInferenceReadinessIssue(for: postProcessingSelection, apiKeyExists: apiKeyExists)
                : settings.enhancementsInferenceReadinessIssue(for: kernelMode, apiKeyExists: apiKeyExists))
            : nil
        if currentMeeting?.id == session.id {
            setPostProcessingReadinessWarning(issue: readinessIssue, mode: kernelMode)
        }
        let applyPostProcessing = (isDictation
            ? readinessIssue == nil
            : Self.shouldApplyEnhancementsPostProcessing(
                settings: settings,
                kernelMode: kernelMode,
                apiKeyExists: apiKeyExists
            )) && (!isDictation || modePostProcessingEnabled)

        let disabledForRecording = isDictation ? !modePostProcessingEnabled : settings.isMeetingPostProcessingDisabled
        let shouldApplyPostProcessing = applyPostProcessing && !disabledForRecording

        if modePostProcessingEnabled, let readinessIssue {
            let reasonCode = readinessIssue.rawValue
            AppLogger.info(
                "Post-processing disabled for this recording: enhancements configuration not ready",
                category: .recordingManager,
                extra: ["reasonCode": reasonCode]
            )
        }

        guard shouldApplyPostProcessing else {
            return skippedUseCaseConfig(
                session: session,
                kernelMode: kernelMode,
                readinessIssue: readinessIssue,
                disabledForRecording: disabledForRecording,
                isDictation: isDictation,
                settings: settings
            )
        }

        let availablePrompts = makeAvailablePrompts(isDictation: isDictation, settings: settings)
        let defaultMeetingPrompt = makeDefaultMeetingPrompt(isDictation: isDictation, settings: settings)
        let prompt = resolvePostProcessingPromptForUseCase(
            meeting: meeting,
            isDictation: isDictation,
            settings: settings,
            defaultMeetingPrompt: defaultMeetingPrompt,
            session: session
        )

        let autoDetectMeetingType = !isDictation && meeting.type == .autodetect

        AppLogger.info(
            "Post-processing configured for this recording",
            category: .recordingManager,
            extra: [
                "mode": kernelMode.rawValue,
                "isDictation": isDictation,
                "promptTitle": prompt?.title ?? "nil",
                "autoDetectMeetingType": autoDetectMeetingType
            ]
        )

        var resolvedContextItems = session.postProcessingContextItems
        if let meetingNotesItem = meetingNotesContextItem(
            from: session.meetingNotesContent,
            capturePurpose: meeting.capturePurpose
        ) {
            if let existingIndex = resolvedContextItems.firstIndex(where: { $0.source == .meetingNotes }) {
                resolvedContextItems[existingIndex] = meetingNotesItem
            } else {
                resolvedContextItems.append(meetingNotesItem)
            }
        }

        let resolvedConfiguration = isDictation
            ? settings.resolvedEnhancementsAIConfiguration(for: postProcessingSelection)
            : settings.resolvedEnhancementsAIConfiguration(for: kernelMode)

        return UseCaseConfig(
            kernelMode: kernelMode,
            applyPostProcessing: true,
            dictationStructuredPostProcessingEnabled: settings.dictationStructuredPostProcessingEnabled,
            postProcessingPrompt: prompt,
            defaultPostProcessingPrompt: autoDetectMeetingType ? defaultMeetingPrompt : nil,
            postProcessingModel: resolvedConfiguration.selectedModel,
            postProcessingIdentity: resolvedConfiguration.provider.modelPerformanceIdentity(modelID: resolvedConfiguration.selectedModel),
            postProcessingConfiguration: DomainPostProcessingConfiguration(
                providerID: resolvedConfiguration.provider.rawValue,
                baseURL: resolvedConfiguration.baseURL,
                modelID: resolvedConfiguration.selectedModel,
                readinessIssue: readinessIssue?.rawValue,
                outputLanguageID: kernelMode == .meeting ? settings.meetingSummaryOutputLanguage.rawValue : nil
            ),
            postProcessingFailureReason: nil,
            autoDetectMeetingType: autoDetectMeetingType,
            availablePrompts: availablePrompts,
            postProcessingContext: session.postProcessingContext,
            postProcessingSystemPrompt: kernelMode == .meeting ? settings.systemPrompt : nil,
            postProcessingContextItems: resolvedContextItems,
            dictationTextHandlingPolicy: session.dictationTextHandlingPolicy,
            dictationTranscriptionConfiguration: session.dictationTranscriptionConfiguration,
            postProcessingSelection: postProcessingSelection
        )
    }

    private func skippedUseCaseConfig(
        session: TranscriptionSessionSnapshot,
        kernelMode: IntelligenceKernelMode,
        readinessIssue: EnhancementsInferenceReadinessIssue?,
        disabledForRecording: Bool,
        isDictation: Bool,
        settings: AppSettingsStore
    ) -> UseCaseConfig {
        let postProcessingSelection = resolvedPostProcessingSelection(session: session, settings: settings)
        let reasonCode = resolveDisabledReasonCode(
            settings: settings,
            readinessIssue: readinessIssue,
            disabledForRecording: disabledForRecording,
            isDictation: isDictation
        )

        AppLogger.info(
            "Post-processing skipped for this recording",
            category: .recordingManager,
            extra: [
                "mode": kernelMode.rawValue,
                "reasonCode": reasonCode,
                "isDictation": isDictation
            ]
        )
        return UseCaseConfig(
            kernelMode: kernelMode,
            applyPostProcessing: false,
            dictationStructuredPostProcessingEnabled: settings.dictationStructuredPostProcessingEnabled,
            postProcessingPrompt: nil,
            defaultPostProcessingPrompt: nil,
            postProcessingModel: nil,
            postProcessingIdentity: nil,
            postProcessingConfiguration: nil,
            postProcessingFailureReason: readinessIssue.map(postProcessingFailureReason(for:)),
            autoDetectMeetingType: false,
            availablePrompts: [],
            postProcessingContext: nil,
            postProcessingSystemPrompt: nil,
            postProcessingContextItems: session.postProcessingContextItems,
            dictationTextHandlingPolicy: session.dictationTextHandlingPolicy,
            dictationTranscriptionConfiguration: session.dictationTranscriptionConfiguration,
            postProcessingSelection: postProcessingSelection
        )
    }

    func postProcessingFailureReason(for issue: EnhancementsInferenceReadinessIssue) -> String {
        switch issue {
        case .missingAPIKey:
            "transcription.post_processing.missing_api_key".localized
        case .missingModel:
            "transcription.post_processing.missing_model".localized
        case .invalidBaseURL:
            "transcription.post_processing.invalid_base_url".localized
        }
    }

    private func resolvedPostProcessingSelection(
        session: TranscriptionSessionSnapshot,
        settings: AppSettingsStore
    ) -> EnhancementsAISelection {
        let dictationSelection = session.kernelMode == .dictation ? session.dictationEnhancementsSelection : nil
        return dictationSelection
            ?? session.postProcessingEnhancementsSelection
            ?? settings.enhancementsSelection(for: session.kernelMode)
    }

    private func resolveDisabledReasonCode(
        settings: AppSettingsStore,
        readinessIssue: EnhancementsInferenceReadinessIssue?,
        disabledForRecording: Bool,
        isDictation: Bool
    ) -> String {
        if !settings.postProcessingEnabled, !isDictation {
            "post_processing.disabled"
        } else if let readinessIssue {
            readinessIssue.rawValue
        } else if disabledForRecording {
            isDictation ? "dictation.prompt.disabled" : "meeting.prompt.disabled"
        } else {
            "post_processing.unknown"
        }
    }

    #if DEBUG
        func debugResolvePostProcessingConfiguration(
            meeting: Meeting,
            settings: AppSettingsStore = .shared
        ) -> PostProcessingConfigurationDebugInfo {
            let snapshot = makeTranscriptionSessionSnapshot(meeting)
            let kernelMode = snapshot.kernelMode
            let config = makeUseCaseConfig(session: snapshot, settings: settings)
            return PostProcessingConfigurationDebugInfo(
                kernelMode: kernelMode,
                applyPostProcessing: config.applyPostProcessing,
                promptId: config.postProcessingPrompt?.id,
                promptTitle: config.postProcessingPrompt?.title
            )
        }
    #endif

    static func shouldApplyEnhancementsPostProcessing(
        settings: AppSettingsStore,
        kernelMode: IntelligenceKernelMode,
        apiKeyExists: ((AIProvider) -> Bool)? = nil
    ) -> Bool {
        let readinessIssue = settings.enhancementsInferenceReadinessIssue(for: kernelMode, apiKeyExists: apiKeyExists)
        let kernelModeEnabled = settings.isIntelligenceKernelModeEnabled(kernelMode)

        let globalPostProcessingEnabled = kernelMode == .dictation || settings.postProcessingEnabled
        return globalPostProcessingEnabled
            && readinessIssue == nil
            && kernelModeEnabled
    }

    func refreshPostProcessingReadinessWarning(
        for kernelMode: IntelligenceKernelMode,
        settings: AppSettingsStore = .shared,
        apiKeyExists: ((AIProvider) -> Bool)? = nil
    ) {
        let resolvedAPIKeyExists = apiKeyExists ?? self.apiKeyExists
        let postProcessingEnabled: Bool = switch kernelMode {
        case .dictation:
            !isPostProcessingDisabled(isDictation: true, settings: settings)
        case .meeting, .assistant:
            settings.postProcessingEnabled
        }
        let issue: EnhancementsInferenceReadinessIssue?
        if postProcessingEnabled {
            if kernelMode == .dictation {
                let selection = matchingDictationStyleForDictation(settings: settings)?.enhancementsSelection
                    ?? settings.enhancementsSelection(for: .dictation)
                issue = settings.enhancementsInferenceReadinessIssue(
                    for: selection,
                    apiKeyExists: resolvedAPIKeyExists
                )
            } else {
                issue = settings.enhancementsInferenceReadinessIssue(for: kernelMode, apiKeyExists: resolvedAPIKeyExists)
            }
        } else {
            issue = nil
        }
        setPostProcessingReadinessWarning(issue: issue, mode: kernelMode)
    }

    func clearPostProcessingReadinessWarning() {
        postProcessingReadinessWarningIssue = nil
        postProcessingReadinessWarningMode = nil
        activePostProcessingKernelMode = nil
    }

    func setPostProcessingReadinessWarning(
        issue: EnhancementsInferenceReadinessIssue?,
        mode: IntelligenceKernelMode
    ) {
        postProcessingReadinessWarningIssue = issue
        postProcessingReadinessWarningMode = issue == nil ? nil : mode
    }

    // MARK: - Prompt Resolution

    func makeAvailablePrompts(isDictation: Bool, settings: AppSettingsStore) -> [DomainPostProcessingPrompt] {
        postProcessingConfigurationProvider.makeAvailablePrompts(
            isDictation: isDictation,
            settings: settings
        )
    }

    func makeDefaultMeetingPrompt(
        isDictation: Bool,
        settings: AppSettingsStore
    ) -> DomainPostProcessingPrompt? {
        postProcessingConfigurationProvider.makeDefaultMeetingPrompt(
            isDictation: isDictation,
            settings: settings
        )
    }

    func resolvePostProcessingPromptForUseCase(
        meeting: Meeting,
        isDictation: Bool,
        settings: AppSettingsStore,
        defaultMeetingPrompt: DomainPostProcessingPrompt?,
        session: TranscriptionSessionSnapshot? = nil
    ) -> DomainPostProcessingPrompt? {
        postProcessingConfigurationProvider.resolvePostProcessingPromptForUseCase(
            meeting: meeting,
            isDictation: isDictation,
            settings: settings,
            defaultMeetingPrompt: defaultMeetingPrompt,
            dictationContext: dictationContextSnapshot(for: session)
        )
    }

    func domainPrompt(from prompt: PostProcessingPrompt) -> DomainPostProcessingPrompt {
        postProcessingConfigurationProvider.domainPrompt(from: prompt)
    }

    // MARK: - Dictation Prompt Overrides

    func promptWithDictationRuleOverrides(
        prompt: PostProcessingPrompt,
        settings: AppSettingsStore,
        session: TranscriptionSessionSnapshot? = nil
    ) -> PostProcessingPrompt {
        postProcessingConfigurationProvider.promptWithDictationRuleOverrides(
            prompt: prompt,
            settings: settings,
            dictationContext: dictationContextSnapshot(for: session)
        )
    }

    func matchingDictationStyleForDictation(
        settings: AppSettingsStore,
        session: TranscriptionSessionSnapshot? = nil
    ) -> DictationStyle? {
        postProcessingConfigurationProvider.matchingDictationStyleForDictation(
            settings: settings,
            dictationContext: dictationContextSnapshot(for: session)
        )
    }

    func effectiveCustomPromptInstructionsForDictation(
        settings: AppSettingsStore,
        session: TranscriptionSessionSnapshot? = nil,
        matchedStyle: DictationStyle? = nil
    ) -> String? {
        postProcessingConfigurationProvider.effectiveCustomPromptInstructionsForDictation(
            settings: settings,
            dictationContext: dictationContextSnapshot(for: session),
            matchedStyle: matchedStyle
        )
    }

    func matchingDictationAppRule(
        settings: AppSettingsStore,
        session: TranscriptionSessionSnapshot? = nil
    ) -> DictationAppRule? {
        postProcessingConfigurationProvider.matchingDictationAppRule(
            settings: settings,
            dictationContext: dictationContextSnapshot(for: session)
        )
    }

    func outputLanguageForDictation(
        settings: AppSettingsStore,
        session: TranscriptionSessionSnapshot? = nil,
        matchedStyle: DictationStyle? = nil
    ) -> DictationOutputLanguage {
        postProcessingConfigurationProvider.outputLanguageForDictation(
            settings: settings,
            dictationContext: dictationContextSnapshot(for: session),
            matchedStyle: matchedStyle
        )
    }

    func shouldForceMarkdownForDictation(
        settings: AppSettingsStore,
        session: TranscriptionSessionSnapshot? = nil,
        matchedStyle: DictationStyle? = nil
    ) -> Bool {
        postProcessingConfigurationProvider.shouldForceMarkdownForDictation(
            settings: settings,
            dictationContext: dictationContextSnapshot(for: session),
            matchedStyle: matchedStyle
        )
    }

    func matchingWebContextTargetForDictation(
        settings: AppSettingsStore,
        session: TranscriptionSessionSnapshot? = nil
    ) -> WebContextTarget? {
        postProcessingConfigurationProvider.matchingWebContextTargetForDictation(
            settings: settings,
            dictationContext: dictationContextSnapshot(for: session)
        )
    }

    func activeBrowserURL(for bundleIdentifier: String?) -> URL? {
        guard let bundleIdentifier else { return nil }
        let normalized = WebTargetDetection.normalizeBundleIdentifier(bundleIdentifier)

        if let provider = browserProviders[normalized] {
            return provider.activeTabURL()
        }

        guard let provider = BrowserProviderRegistry.provider(for: bundleIdentifier) else {
            return nil
        }

        browserProviders[normalized] = provider
        return provider.activeTabURL()
    }

    func promptWithMeetingSummaryOverrides(
        prompt: PostProcessingPrompt
    ) -> PostProcessingPrompt {
        postProcessingConfigurationProvider.promptWithMeetingSummaryOverrides(prompt: prompt)
    }

    // MARK: - Mode Detection

    func isDictationMode(
        for meeting: Meeting?,
        capturePurposeOverride: CapturePurpose? = nil
    ) -> Bool {
        if let capturePurposeOverride {
            return capturePurposeOverride == .dictation
        }

        if isRecording || isTranscribing {
            return currentCapturePurpose == .dictation
        }

        return meeting?.capturePurpose == .dictation || currentCapturePurpose == .dictation
    }

    func postProcessingKernelMode(
        for meeting: Meeting?,
        capturePurposeOverride: CapturePurpose? = nil
    ) -> IntelligenceKernelMode {
        if let activePostProcessingKernelMode, capturePurposeOverride == nil {
            return activePostProcessingKernelMode
        }

        return isDictationMode(for: meeting, capturePurposeOverride: capturePurposeOverride) ? .dictation : .meeting
    }

    func isPostProcessingDisabled(isDictation: Bool, settings: AppSettingsStore) -> Bool {
        if isDictation {
            return !(matchingDictationStyleForDictation(settings: settings)?.postProcessingEnabled ?? true)
        }
        return settings.isMeetingPostProcessingDisabled
    }

    private func dictationContextSnapshot(
        for session: TranscriptionSessionSnapshot?
    ) -> DictationContextSnapshot {
        DictationContextSnapshot(
            bundleIdentifier: session?.dictationStartBundleIdentifier ?? dictationStartBundleIdentifier,
            activeURL: session?.dictationStartURL ?? dictationStartURL,
            outputLanguageOverride: session?.dictationSessionOutputLanguageOverride ?? dictationSessionOutputLanguageOverride,
            style: session?.dictationStyle
        )
    }

    private func dictationPostProcessingEnabled(
        for session: TranscriptionSessionSnapshot,
        settings: AppSettingsStore
    ) -> Bool {
        guard session.kernelMode == .dictation else { return settings.postProcessingEnabled }
        return session.dictationPostProcessingEnabled
            ?? matchingDictationStyleForDictation(settings: settings, session: session)?.postProcessingEnabled
            ?? true
    }
}

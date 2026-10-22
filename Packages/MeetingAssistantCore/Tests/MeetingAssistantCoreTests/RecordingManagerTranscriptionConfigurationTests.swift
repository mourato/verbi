import Foundation
@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreUI
import XCTest

@MainActor
extension RecordingManagerTests {
    func testModeConfigurationIsStableDuringSession() async throws {
        let manager = try XCTUnwrap(manager)
        let settings = AppSettingsStore.shared
        let originalStyles = settings.dictationStyles
        let originalAutoCopy = settings.autoCopyTranscriptionToClipboard
        let originalReplacementRules = settings.vocabularyReplacementRules
        defer {
            settings.dictationStyles = originalStyles
            settings.autoCopyTranscriptionToClipboard = originalAutoCopy
            settings.vocabularyReplacementRules = originalReplacementRules
        }
        let snapshottedReplacementRules = [VocabularyReplacementRule(find: "captured", replace: "stable")]
        settings.vocabularyReplacementRules = snapshottedReplacementRules

        let snapshottedPolicy = DictationTextHandlingPolicy(
            autoCopyToClipboard: true,
            autoPasteToActiveApp: false,
            smartSpacingAndCapitalization: true,
            smartParagraphs: false,
        )
        let snapshottedTranscription = DictationTranscriptionConfiguration(
            selection: TranscriptionProviderSelection(provider: .groq, selectedModel: "whisper-large-v3"),
            inputLanguageCode: "pt-BR",
        )
        var styles = settings.dictationStyles
        let defaultIndex = try XCTUnwrap(styles.firstIndex(where: \.isDefault))
        styles[defaultIndex] = makeDictationStyle(
            styles[defaultIndex],
            textHandlingPolicy: snapshottedPolicy,
            transcriptionConfiguration: snapshottedTranscription,
        )
        settings.dictationStyles = styles

        await manager.startRecording(source: .microphone)
        XCTAssertTrue(manager.isRecording)

        var mutatedStyles = settings.dictationStyles
        let mutatedIndex = try XCTUnwrap(mutatedStyles.firstIndex(where: \.isDefault))
        mutatedStyles[mutatedIndex] = makeDictationStyle(
            mutatedStyles[mutatedIndex],
            textHandlingPolicy: DictationTextHandlingPolicy(
                autoCopyToClipboard: false,
                autoPasteToActiveApp: true,
                smartSpacingAndCapitalization: false,
                smartParagraphs: true,
            ),
            transcriptionConfiguration: DictationTranscriptionConfiguration(
                selection: .default,
                inputLanguageCode: "en",
            ),
        )
        settings.dictationStyles = mutatedStyles
        settings.autoCopyTranscriptionToClipboard = false
        settings.vocabularyReplacementRules = [VocabularyReplacementRule(find: "captured", replace: "mutated")]

        let meeting = try XCTUnwrap(manager.currentMeeting)
        let session = manager.makeTranscriptionSessionSnapshot(meeting)

        XCTAssertEqual(session.dictationTextHandlingPolicy, snapshottedPolicy)
        XCTAssertEqual(session.dictationTranscriptionConfiguration, snapshottedTranscription)
        XCTAssertEqual(session.vocabularySnapshot.replacementRules, snapshottedReplacementRules)

        await manager.cancelRecording()
    }

    func testMeetingPostProcessingSelectionIsStableDuringSession() async throws {
        let manager = try XCTUnwrap(manager)
        let settings = AppSettingsStore.shared
        let originalSelection = settings.enhancementsAISelection
        let originalPostProcessingEnabled = settings.postProcessingEnabled
        let frozenSelection = EnhancementsAISelection(
            provider: .anthropic,
            selectedModel: "frozen-meeting-model",
            registrationID: UUID(),
        )
        defer {
            settings.enhancementsAISelection = originalSelection
            settings.postProcessingEnabled = originalPostProcessingEnabled
        }

        settings.enhancementsAISelection = frozenSelection
        settings.postProcessingEnabled = true
        await manager.startRecording(source: .all)
        let meeting = try XCTUnwrap(manager.currentMeeting)
        let session = manager.makeTranscriptionSessionSnapshot(meeting)

        settings.enhancementsAISelection = EnhancementsAISelection(
            provider: .openai,
            selectedModel: "mutated-meeting-model",
        )
        manager.overrideCurrentMeetingType(.standup)
        let overriddenMeeting = try XCTUnwrap(manager.currentMeeting)
        let overriddenSession = manager.makeTranscriptionSessionSnapshot(overriddenMeeting)
        let config = try XCTUnwrap(session.useCaseConfig)
        let overriddenConfig = try XCTUnwrap(overriddenSession.useCaseConfig)

        XCTAssertEqual(session.postProcessingEnhancementsSelection, frozenSelection)
        XCTAssertEqual(config.postProcessingSelection, frozenSelection)
        XCTAssertEqual(overriddenConfig.postProcessingPrompt?.id, PostProcessingPrompt.standup.id)
        XCTAssertFalse(overriddenConfig.autoDetectMeetingType)

        await manager.cancelRecording()
    }

    func testPostProcessingPromptSnapshotWinsAfterSettingsMutation() async throws {
        let manager = try XCTUnwrap(manager)
        let settings = AppSettingsStore.shared
        let originalPrompts = settings.meetingPrompts
        let originalSelectedPromptID = settings.selectedPromptId
        defer {
            settings.meetingPrompts = originalPrompts
            settings.selectedPromptId = originalSelectedPromptID
        }

        let capturedPrompt = PostProcessingPrompt(title: "Captured", promptText: "Use captured", isActive: true)
        let mutatedPrompt = PostProcessingPrompt(title: "Mutated", promptText: "Use mutated", isActive: true)
        settings.meetingPrompts = [capturedPrompt]
        settings.selectedPromptId = capturedPrompt.id
        let snapshot = manager.makePostProcessingPromptSnapshot(isDictation: false, settings: settings)

        settings.meetingPrompts = [mutatedPrompt]
        settings.selectedPromptId = mutatedPrompt.id

        let request = DomainPostProcessingRequest(
            mode: .meeting,
            configuration: DomainPostProcessingConfiguration(
                providerID: LLMProvider.openai.rawValue,
                baseURL: LLMProvider.openai.defaultBaseURL,
                modelID: "captured-model",
            ),
            useStructuredPipeline: false,
        )
        let resolved = await manager.resolvePostProcessingPrompt(
            rawText: "meeting transcript",
            isDictation: false,
            meetingType: .general,
            snapshot: snapshot,
            request: request,
        )

        XCTAssertEqual(resolved.id, capturedPrompt.id)
        XCTAssertEqual(resolved.promptText, capturedPrompt.promptText)
    }

    func testPostProcessingRequestOverridePreservesDisabledOperation() async throws {
        let manager = try XCTUnwrap(manager)
        let postProcessing = try XCTUnwrap(mockPostProcessing)
        let settings = AppSettingsStore.shared
        let overrides = RecordingManager.PostProcessingRequestOverrides(
            applyPostProcessing: false,
            selection: EnhancementsAISelection(provider: .openai, selectedModel: "captured-model"),
            configuration: DomainPostProcessingConfiguration(
                providerID: LLMProvider.openai.rawValue,
                baseURL: LLMProvider.openai.defaultBaseURL,
                modelID: "captured-model",
            ),
            useStructuredPipeline: true,
            systemPromptOverride: "captured system prompt",
            promptSnapshot: manager.makePostProcessingPromptSnapshot(isDictation: false, settings: settings),
        )

        let result = await manager.applyPostProcessing(
            postProcessingInput: "meeting transcript",
            meeting: CaptureSession(app: .zoom, capturePurpose: .meeting),
            qualityProfile: nil,
            requestOverrides: overrides,
        )

        XCTAssertEqual(result.failureReason, "Post-processing is disabled globally.")
        XCTAssertEqual(postProcessing.processTranscriptionCallCount, 0)
    }

    func testPostProcessingUsesModeConfigurationFallback() async throws {
        let manager = try XCTUnwrap(manager)
        let postProcessing = try XCTUnwrap(mockPostProcessing)
        let settings = AppSettingsStore.shared
        let originalMeetingSelection = settings.enhancementsAISelection
        let originalDictationSelection = settings.enhancementsDictationAISelection
        let originalProviderModels = settings.enhancementsProviderSelectedModels
        let originalPostProcessingEnabled = settings.postProcessingEnabled
        defer {
            settings.enhancementsAISelection = originalMeetingSelection
            settings.enhancementsDictationAISelection = originalDictationSelection
            settings.enhancementsProviderSelectedModels = originalProviderModels
            settings.postProcessingEnabled = originalPostProcessingEnabled
        }

        settings.enhancementsProviderSelectedModels = [:]
        settings.enhancementsAISelection = EnhancementsAISelection(provider: .custom, selectedModel: "")
        settings.enhancementsDictationAISelection = EnhancementsAISelection(
            provider: .anthropic,
            selectedModel: "sibling-model",
        )
        settings.postProcessingEnabled = true

        let result = await manager.applyPostProcessing(
            postProcessingInput: "meeting transcript",
            meeting: CaptureSession(app: .zoom, capturePurpose: .meeting),
            qualityProfile: nil,
        )

        XCTAssertNil(result.failureReason)
        XCTAssertEqual(postProcessing.lastStructuredRequest?.configuration.provider, .anthropic)
        XCTAssertEqual(postProcessing.lastStructuredRequest?.configuration.selectedModel, "sibling-model")
    }

    func testStopSnapshot_OutputLanguageChosenMidRecording_ReResolvesDictationPrompt() throws {
        let manager = try XCTUnwrap(manager)
        let settings = AppSettingsStore.shared
        let originalPostProcessing = settings.postProcessingEnabled
        let originalDictationSelection = settings.enhancementsDictationAISelection
        defer {
            settings.postProcessingEnabled = originalPostProcessing
            settings.enhancementsDictationAISelection = originalDictationSelection
            manager.setDictationSessionOutputLanguageOverride(nil)
            manager.activeUseCaseConfig = nil
        }

        settings.postProcessingEnabled = true
        settings.enhancementsDictationAISelection = EnhancementsAISelection(
            provider: .openai,
            selectedModel: "gpt-4o-mini",
        )

        let meeting = CaptureSession(app: .unknown, capturePurpose: .dictation, startTime: Date())
        let startSnapshot = manager.makeTranscriptionSessionSnapshot(meeting)
        let startPrompt = try XCTUnwrap(startSnapshot.useCaseConfig?.postProcessingPrompt)
        XCTAssertFalse(startPrompt.content.contains("<OUTPUT_LANGUAGE>"))

        manager.activeUseCaseConfig = startSnapshot.useCaseConfig
        manager.setDictationSessionOutputLanguageOverride(.english)

        let stopSnapshot = manager.makeTranscriptionSessionSnapshot(meeting)
        let stopPrompt = try XCTUnwrap(stopSnapshot.useCaseConfig?.postProcessingPrompt)
        XCTAssertTrue(
            stopPrompt.content.contains("Translate the final output to English."),
            "Expected output language chosen during recording to reach the stop-time prompt",
        )
    }
}

private func makeDictationStyle(
    _ style: DictationStyle,
    textHandlingPolicy: DictationTextHandlingPolicy,
    transcriptionConfiguration: DictationTranscriptionConfiguration,
) -> DictationStyle {
    DictationStyle(
        id: style.id,
        name: style.name,
        iconSymbol: style.iconSymbol,
        promptInstructions: style.promptInstructions,
        postProcessingEnabled: style.postProcessingEnabled,
        forceMarkdownOutput: style.forceMarkdownOutput,
        replaceBasePrompt: style.replaceBasePrompt,
        outputLanguage: style.outputLanguage,
        targets: [],
        contextSourcePolicy: style.contextSourcePolicy,
        enhancementsSelection: style.enhancementsSelection,
        isDefault: true,
        textHandlingPolicy: textHandlingPolicy,
        transcriptionConfiguration: transcriptionConfiguration,
    )
}

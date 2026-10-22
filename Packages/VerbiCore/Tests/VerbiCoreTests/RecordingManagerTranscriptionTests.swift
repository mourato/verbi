import Foundation
@testable import VerbiCore
@testable import VerbiCoreUI
import XCTest

// swiftlint:disable function_body_length

@MainActor
extension RecordingManagerTests {
    func testStopRecordingUsesFullFileHandoffThroughLifecycle() async throws {
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)
        let mockTranscription = try XCTUnwrap(mockTranscription)
        let mockStorage = try XCTUnwrap(mockStorage)
        let settings = AppSettingsStore.shared
        let originalMergeSetting = settings.shouldMergeAudioFiles
        let originalSilenceSetting = settings.removeSilenceBeforeProcessing
        settings.shouldMergeAudioFiles = false
        settings.removeSilenceBeforeProcessing = false
        defer {
            settings.shouldMergeAudioFiles = originalMergeSetting
            settings.removeSilenceBeforeProcessing = originalSilenceSetting
        }

        await manager.startRecording()
        let rawURL = try XCTUnwrap(mockMic.currentRecordingURL)
        let finalURL = mockStorage.recordingsDirectory.appendingPathComponent("mock_merged.wav")
        try writeTestAudioFile(at: rawURL)

        await manager.stopRecording()

        XCTAssertEqual(mockTranscription.lastTranscribeAudioURL, finalURL)
        XCTAssertGreaterThan(mockTranscription.fileTranscribeCallCount, 0)
        XCTAssertFalse(manager.isRecording)
    }

    func testStopRecording_DictationUsesDictationPromptSelection() async throws {
        let manager = try XCTUnwrap(manager)
        let settings = AppSettingsStore.shared

        let originalPostProcessing = settings.postProcessingEnabled
        let originalMeetingSelection = settings.enhancementsAISelection
        let originalDictationSelection = settings.enhancementsDictationAISelection
        let originalMeetingPrompts = settings.meetingPrompts
        let originalDictationPrompts = settings.dictationPrompts
        let originalSelectedPromptId = settings.selectedPromptId
        let originalDictationSelectedPromptId = settings.dictationSelectedPromptId
        let originalDictationStyles = settings.dictationStyles

        let meetingPrompt = PostProcessingPrompt(
            title: "Meeting Prompt Test",
            promptText: "MEETING_PROMPT_SENTINEL",
            isActive: true,
        )
        let dictationPrompt = PostProcessingPrompt(
            title: "Dictation Prompt Test",
            promptText: "DICTATION_PROMPT_SENTINEL",
            isActive: true,
        )
        let dictationSelection = EnhancementsAISelection(provider: .openai, selectedModel: "gpt-4o-mini")

        defer {
            settings.postProcessingEnabled = originalPostProcessing
            settings.enhancementsAISelection = originalMeetingSelection
            settings.enhancementsDictationAISelection = originalDictationSelection
            settings.meetingPrompts = originalMeetingPrompts
            settings.dictationPrompts = originalDictationPrompts
            settings.selectedPromptId = originalSelectedPromptId
            settings.dictationSelectedPromptId = originalDictationSelectedPromptId
            settings.dictationStyles = originalDictationStyles
        }

        settings.postProcessingEnabled = true
        settings.enhancementsAISelection = EnhancementsAISelection(provider: .openai, selectedModel: "gpt-4o-mini")
        settings.enhancementsDictationAISelection = dictationSelection
        // Apply enhancementsSelection to the default dictation style so the snapshot picks it up.
        var updatedStyles = settings.dictationStyles
        if let defaultIndex = updatedStyles.firstIndex(where: { $0.isDefault }) {
            updatedStyles[defaultIndex] = DictationStyle(
                id: updatedStyles[defaultIndex].id,
                name: updatedStyles[defaultIndex].name,
                iconSymbol: updatedStyles[defaultIndex].iconSymbol,
                promptInstructions: updatedStyles[defaultIndex].promptInstructions,
                postProcessingEnabled: true,
                forceMarkdownOutput: updatedStyles[defaultIndex].forceMarkdownOutput,
                replaceBasePrompt: updatedStyles[defaultIndex].replaceBasePrompt,
                outputLanguage: updatedStyles[defaultIndex].outputLanguage,
                targets: updatedStyles[defaultIndex].targets,
                contextSourcePolicy: updatedStyles[defaultIndex].contextSourcePolicy,
                enhancementsSelection: dictationSelection,
                isDefault: true,
                textHandlingPolicy: updatedStyles[defaultIndex].textHandlingPolicy,
                transcriptionConfiguration: updatedStyles[defaultIndex].transcriptionConfiguration,
            )
        }
        settings.dictationStyles = updatedStyles
        settings.meetingPrompts = [meetingPrompt]
        settings.dictationPrompts = [dictationPrompt]
        settings.selectedPromptId = meetingPrompt.id
        settings.dictationSelectedPromptId = dictationPrompt.id

        await manager.startRecording(source: .microphone)
        XCTAssertTrue(manager.isRecording)

        let meeting = CaptureSession(app: .unknown)
        let configuration = manager.debugResolvePostProcessingConfiguration(meeting: meeting, settings: settings)

        XCTAssertEqual(configuration.kernelMode, .dictation)
        XCTAssertTrue(configuration.applyPostProcessing)
        XCTAssertEqual(configuration.promptId, dictationPrompt.id)
        XCTAssertEqual(configuration.promptTitle, dictationPrompt.title)

        await manager.cancelRecording()
    }

    func testStopRecording_DictationRunsPostProcessing() async throws {
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)
        let mockPostProcessing = try XCTUnwrap(mockPostProcessing)
        let settings = AppSettingsStore.shared
        let originalPostProcessing = settings.postProcessingEnabled
        let originalDictationSelection = settings.enhancementsDictationAISelection
        let originalDictationStyles = settings.dictationStyles
        let originalDictationPromptID = settings.dictationSelectedPromptId
        let originalMergeSetting = settings.shouldMergeAudioFiles
        let originalSilenceSetting = settings.removeSilenceBeforeProcessing
        let selection = EnhancementsAISelection(provider: .openai, selectedModel: "gpt-4o-mini")

        defer {
            settings.postProcessingEnabled = originalPostProcessing
            settings.enhancementsDictationAISelection = originalDictationSelection
            settings.dictationStyles = originalDictationStyles
            settings.dictationSelectedPromptId = originalDictationPromptID
            settings.shouldMergeAudioFiles = originalMergeSetting
            settings.removeSilenceBeforeProcessing = originalSilenceSetting
        }

        settings.postProcessingEnabled = true
        settings.enhancementsDictationAISelection = selection
        settings.dictationStyles = settings.dictationStyles.map { style in
            var updated = style
            updated.enhancementsSelection = selection
            updated.postProcessingEnabled = true
            return updated
        }
        settings.dictationSelectedPromptId = PostProcessingPrompt.defaultPrompt.id
        settings.shouldMergeAudioFiles = false
        settings.removeSilenceBeforeProcessing = false

        await manager.startRecording(source: .microphone)
        let rawURL = try XCTUnwrap(mockMic.currentRecordingURL)
        try writeTestAudioFile(at: rawURL)

        await manager.stopRecording()

        XCTAssertGreaterThan(mockPostProcessing.processTranscriptionCallCount, 0)
        XCTAssertEqual(mockPostProcessing.lastPromptTitle, PostProcessingPrompt.defaultPrompt.title)
    }

    func testDictationPostProcessingUsesResolvedSelectionWhenStyleHasNoSelection() async throws {
        let manager = try XCTUnwrap(manager)
        let settings = AppSettingsStore.shared
        let originalPostProcessing = settings.postProcessingEnabled
        let originalDictationSelection = settings.enhancementsDictationAISelection
        let originalDictationStyles = settings.dictationStyles
        defer {
            settings.postProcessingEnabled = originalPostProcessing
            settings.enhancementsDictationAISelection = originalDictationSelection
            settings.dictationStyles = originalDictationStyles
        }

        settings.postProcessingEnabled = false
        settings.enhancementsDictationAISelection = EnhancementsAISelection(provider: .openai, selectedModel: "gpt-4o-mini")
        settings.dictationStyles = settings.dictationStyles.map { style in
            var updated = style
            updated.enhancementsSelection = nil
            updated.postProcessingEnabled = true
            return updated
        }

        await manager.startRecording(source: .microphone)
        let configuration = manager.debugResolvePostProcessingConfiguration(meeting: CaptureSession(app: .unknown), settings: settings)
        await manager.cancelRecording()

        XCTAssertTrue(configuration.applyPostProcessing)
    }

    func testStopRecording_MeetingUsesMeetingPromptSelection() async throws {
        let manager = try XCTUnwrap(manager)
        let settings = AppSettingsStore.shared

        let originalPostProcessing = settings.postProcessingEnabled
        let originalMeetingSelection = settings.enhancementsAISelection
        let originalDictationSelection = settings.enhancementsDictationAISelection
        let originalMeetingPrompts = settings.meetingPrompts
        let originalDictationPrompts = settings.dictationPrompts
        let originalSelectedPromptId = settings.selectedPromptId
        let originalDictationSelectedPromptId = settings.dictationSelectedPromptId
        let originalDictationStyles = settings.dictationStyles

        let meetingPrompt = PostProcessingPrompt(
            title: "Meeting Prompt Test 2",
            promptText: "MEETING_PROMPT_SENTINEL_2",
            isActive: true,
        )
        let dictationPrompt = PostProcessingPrompt(
            title: "Dictation Prompt Test 2",
            promptText: "DICTATION_PROMPT_SENTINEL_2",
            isActive: true,
        )

        defer {
            settings.postProcessingEnabled = originalPostProcessing
            settings.enhancementsAISelection = originalMeetingSelection
            settings.enhancementsDictationAISelection = originalDictationSelection
            settings.meetingPrompts = originalMeetingPrompts
            settings.dictationPrompts = originalDictationPrompts
            settings.selectedPromptId = originalSelectedPromptId
            settings.dictationSelectedPromptId = originalDictationSelectedPromptId
            settings.dictationStyles = originalDictationStyles
        }

        settings.postProcessingEnabled = true
        settings.enhancementsAISelection = EnhancementsAISelection(provider: .openai, selectedModel: "gpt-4o-mini")
        settings.enhancementsDictationAISelection = EnhancementsAISelection(provider: .openai, selectedModel: "gpt-4o-mini")
        settings.meetingPrompts = [meetingPrompt]
        settings.dictationPrompts = [dictationPrompt]
        settings.selectedPromptId = meetingPrompt.id
        settings.dictationSelectedPromptId = dictationPrompt.id

        await manager.startRecording(source: .all)
        XCTAssertTrue(manager.isRecording)

        let meeting = CaptureSession(app: .zoom)
        let configuration = manager.debugResolvePostProcessingConfiguration(meeting: meeting, settings: settings)

        XCTAssertEqual(configuration.kernelMode, .meeting)
        XCTAssertTrue(configuration.applyPostProcessing)
        XCTAssertEqual(configuration.promptId, meetingPrompt.id)
        XCTAssertEqual(configuration.promptTitle, meetingPrompt.title)

        await manager.cancelRecording()
    }

    // MARK: - Error Handling Tests

    func testStartRecording_FailsWhenSystemRecorderFails() async throws {
        // Given
        let mockMic = try XCTUnwrap(mockMic)
        let mockSystem = try XCTUnwrap(mockSystem)

        mockMic.permissionGranted = true
        mockSystem.permissionGranted = true
        mockMic.shouldFailStart = true

        // When
        do {
            try await mockMic.startRecording(to: URL(fileURLWithPath: "/tmp/test.m4a"), retryCount: 0)
            XCTFail("Expected error to be thrown")
        } catch {
            // Then
            XCTAssertNotNil(error)
        }
    }

    func testStopRecording_HandlesErrorGracefully() async throws {
        // Given
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)
        let mockSystem = try XCTUnwrap(mockSystem)

        mockMic.permissionGranted = true
        mockSystem.permissionGranted = true

        await manager.startRecording()

        // When - stopping should not throw even if cleanup fails
        await manager.stopRecording()

        // Then - should have stopped
        XCTAssertFalse(manager.isRecording)
    }

    func testStopRecording_WhenTranscriptionFails_CleansManagerAndReleasesExclusivity() async throws {
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)
        let mockTranscription = try XCTUnwrap(mockTranscription)

        mockTranscription.shouldFailTranscription = true
        await manager.startRecording()
        let rawURL = try XCTUnwrap(mockMic.currentRecordingURL)
        try writeTestAudioFile(at: rawURL)

        await manager.stopRecording()

        XCTAssertGreaterThan(mockTranscription.fileTranscribeCallCount, 0)
        XCTAssertFalse(manager.isRecording)
        XCTAssertFalse(manager.isStartingRecording)
        XCTAssertFalse(manager.isTranscribing)
        XCTAssertNil(manager.currentMeeting)
        XCTAssertNil(manager.currentCapturePurpose)
        let activeMode = await RecordingExclusivityCoordinator.shared.activeRecordingMode()
        XCTAssertNil(activeMode)
    }

    func testStopRecording_WithSilenceRemovalDisabled_UsesOriginalAudio() async throws {
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)
        let mockSystem = try XCTUnwrap(mockSystem)
        let mockTranscription = try XCTUnwrap(mockTranscription)
        let mockCompactor = try XCTUnwrap(mockAudioSilenceCompactor)
        let settings = AppSettingsStore.shared

        settings.removeSilenceBeforeProcessing = false
        mockMic.permissionGranted = true
        mockSystem.permissionGranted = true

        await manager.startRecording()
        let rawURL = try XCTUnwrap(mockMic.currentRecordingURL)
        try writeTestAudioFile(at: rawURL)

        await manager.stopRecording()

        XCTAssertEqual(mockTranscription.lastTranscribeAudioURL, rawURL)
        XCTAssertEqual(mockCompactor.compactCallCount, 0)
    }

    func testStopRecording_WithSilenceRemovalEnabled_UsesTemporaryCompactedAudioAndCleansItUp() async throws {
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)
        let mockSystem = try XCTUnwrap(mockSystem)
        let mockTranscription = try XCTUnwrap(mockTranscription)
        let mockCompactor = try XCTUnwrap(mockAudioSilenceCompactor)
        let settings = AppSettingsStore.shared

        settings.audioFormat = .m4a
        settings.removeSilenceBeforeProcessing = true
        mockMic.permissionGranted = true
        mockSystem.permissionGranted = true

        await manager.startRecording()
        let rawURL = try XCTUnwrap(mockMic.currentRecordingURL)
        try writeTestAudioFile(at: rawURL)

        await manager.stopRecording()

        let compactedURL = try XCTUnwrap(mockCompactor.lastOutputURL)
        XCTAssertEqual(mockTranscription.lastTranscribeAudioURL, compactedURL)
        XCTAssertEqual(mockCompactor.lastFormat, .wav)
        XCTAssertEqual(compactedURL.pathExtension.lowercased(), "wav")
        XCTAssertFalse(FileManager.default.fileExists(atPath: compactedURL.path))
    }

    func testStopRecording_WithRemoteGroqTranscription_SkipsSilenceCompaction() async throws {
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)
        let mockSystem = try XCTUnwrap(mockSystem)
        let mockTranscription = try XCTUnwrap(mockTranscription)
        let mockCompactor = try XCTUnwrap(mockAudioSilenceCompactor)
        let settings = AppSettingsStore.shared
        let originalAudioFormat = settings.audioFormat
        let originalRemoveSilence = settings.removeSilenceBeforeProcessing
        let originalSelection = settings.transcriptionDictationSelection
        let originalModels = settings.transcriptionProviderSelectedModels

        defer {
            settings.audioFormat = originalAudioFormat
            settings.removeSilenceBeforeProcessing = originalRemoveSilence
            settings.transcriptionDictationSelection = originalSelection
            settings.transcriptionProviderSelectedModels = originalModels
        }

        settings.audioFormat = .m4a
        settings.removeSilenceBeforeProcessing = true
        settings.updateTranscriptionDictationSelection(
            provider: .groq,
            model: "whisper-large-v3-turbo",
        )
        mockMic.permissionGranted = true
        mockSystem.permissionGranted = true

        await manager.startCapture(purpose: .dictation)
        let rawURL = try XCTUnwrap(mockMic.currentRecordingURL)
        try writeTestAudioFile(at: rawURL)

        await manager.stopRecording()

        XCTAssertEqual(mockTranscription.lastTranscribeAudioURL, rawURL)
        XCTAssertEqual(mockCompactor.compactCallCount, 0)
    }

    func testStopRecording_WhenCompactionFails_FallsBackToOriginalAudio() async throws {
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)
        let mockSystem = try XCTUnwrap(mockSystem)
        let mockTranscription = try XCTUnwrap(mockTranscription)
        let mockCompactor = try XCTUnwrap(mockAudioSilenceCompactor)
        let settings = AppSettingsStore.shared

        settings.removeSilenceBeforeProcessing = true
        mockCompactor.shouldThrow = true
        mockMic.permissionGranted = true
        mockSystem.permissionGranted = true

        await manager.startRecording()
        let rawURL = try XCTUnwrap(mockMic.currentRecordingURL)
        try writeTestAudioFile(at: rawURL)

        await manager.stopRecording()

        XCTAssertEqual(mockTranscription.lastTranscribeAudioURL, rawURL)
    }

    func testRetryTranscription_ReappliesSilenceCompactionAndCleansTemporaryCopy() async throws {
        let manager = try XCTUnwrap(manager)
        let mockTranscription = try XCTUnwrap(mockTranscription)
        let mockCompactor = try XCTUnwrap(mockAudioSilenceCompactor)
        let settings = AppSettingsStore.shared

        settings.removeSilenceBeforeProcessing = true

        let rawURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        try writeTestAudioFile(at: rawURL)
        defer { try? FileManager.default.removeItem(at: rawURL) }

        let transcription = CaptureArtifact(
            meeting: CaptureSession(app: .zoom, capturePurpose: .meeting, audioFilePath: rawURL.path),
            text: "Existing",
            rawText: "Existing",
            processedContent: nil,
            postProcessingPromptId: nil,
            postProcessingPromptTitle: nil,
            language: "en",
            modelName: "test-model",
        )

        await manager.retryTranscription(for: transcription)

        let compactedURL = try XCTUnwrap(mockCompactor.lastOutputURL)
        XCTAssertEqual(mockTranscription.lastTranscribeAudioURL, compactedURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: compactedURL.path))
    }

    func testRetryTranscription_RemoteDictationOverrideSkipsHealthCheckAndSilenceCompaction() async throws {
        let manager = try XCTUnwrap(manager)
        let mockTranscription = try XCTUnwrap(mockTranscription)
        let mockCompactor = try XCTUnwrap(mockAudioSilenceCompactor)
        let settings = AppSettingsStore.shared

        let originalRemoveSilence = settings.removeSilenceBeforeProcessing
        let originalSelection = settings.transcriptionDictationSelection
        defer {
            settings.removeSilenceBeforeProcessing = originalRemoveSilence
            settings.transcriptionDictationSelection = originalSelection
        }

        settings.removeSilenceBeforeProcessing = true
        settings.updateTranscriptionDictationSelection(
            provider: .local,
            model: LocalTranscriptionModel.parakeetTdt06BV3.rawValue,
        )
        readyRetryProviders = [.groq]
        mockTranscription.shouldFailHealthCheck = true

        let rawURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        try writeTestAudioFile(at: rawURL)
        defer { try? FileManager.default.removeItem(at: rawURL) }

        let transcription = CaptureArtifact(
            meeting: CaptureSession(app: .unknown, capturePurpose: .dictation, audioFilePath: rawURL.path),
            text: "Existing",
            rawText: "Existing",
            processedContent: nil,
            postProcessingPromptId: nil,
            postProcessingPromptTitle: nil,
            language: "en",
            modelName: "test-model",
        )

        await manager.retryTranscription(
            for: transcription,
            selectionOverride: TranscriptionProviderSelection(
                provider: .groq,
                selectedModel: TranscriptionProvider.groqPresetModelIDs[0],
            ),
        )

        XCTAssertEqual(mockTranscription.healthCheckCallCount, 0)
        XCTAssertEqual(mockCompactor.compactCallCount, 0)
        XCTAssertEqual(mockTranscription.lastTranscribeAudioURL, rawURL)
    }

    func testRetryTranscription_RemoteMeetingOverrideFallsBackToConfiguredLocalSelection() async throws {
        let manager = try XCTUnwrap(manager)
        let mockTranscription = try XCTUnwrap(mockTranscription)
        let mockCompactor = try XCTUnwrap(mockAudioSilenceCompactor)
        let settings = AppSettingsStore.shared
        let originalRemoveSilence = settings.removeSilenceBeforeProcessing
        defer {
            settings.removeSilenceBeforeProcessing = originalRemoveSilence
        }

        settings.removeSilenceBeforeProcessing = true
        readyRetryProviders = [.groq]

        let rawURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        try writeTestAudioFile(at: rawURL)
        defer { try? FileManager.default.removeItem(at: rawURL) }

        let transcription = CaptureArtifact(
            meeting: CaptureSession(app: .zoom, capturePurpose: .meeting, audioFilePath: rawURL.path),
            text: "Existing",
            rawText: "Existing",
            processedContent: nil,
            postProcessingPromptId: nil,
            postProcessingPromptTitle: nil,
            language: "en",
            modelName: "test-model",
        )

        await manager.retryTranscription(
            for: transcription,
            selectionOverride: TranscriptionProviderSelection(
                provider: .groq,
                selectedModel: TranscriptionProvider.groqPresetModelIDs[0],
            ),
        )

        let compactedURL = try XCTUnwrap(mockCompactor.lastOutputURL)
        XCTAssertEqual(mockTranscription.healthCheckCallCount, 1)
        XCTAssertEqual(mockCompactor.compactCallCount, 1)
        XCTAssertEqual(mockTranscription.lastTranscribeAudioURL, compactedURL)
    }

    func testApplyPostProcessing_UsesDictationPromptForImportedDictationAudio() async throws {
        let manager = try XCTUnwrap(manager)
        let mockPostProcessing = try XCTUnwrap(mockPostProcessing)
        let settings = AppSettingsStore.shared

        let originalPostProcessingEnabled = settings.postProcessingEnabled
        let originalSelectedPromptId = settings.selectedPromptId
        let originalDictationSelectedPromptId = settings.dictationSelectedPromptId
        let originalMeetingPrompts = settings.meetingPrompts
        let originalDictationPrompts = settings.dictationPrompts
        let originalMeetingSelection = settings.enhancementsAISelection
        let originalDictationSelection = settings.enhancementsDictationAISelection
        let originalProviderModels = settings.enhancementsProviderSelectedModels

        defer {
            settings.postProcessingEnabled = originalPostProcessingEnabled
            settings.selectedPromptId = originalSelectedPromptId
            settings.dictationSelectedPromptId = originalDictationSelectedPromptId
            settings.meetingPrompts = originalMeetingPrompts
            settings.dictationPrompts = originalDictationPrompts
            settings.enhancementsAISelection = originalMeetingSelection
            settings.enhancementsDictationAISelection = originalDictationSelection
            settings.enhancementsProviderSelectedModels = originalProviderModels
        }

        let meetingPrompt = PostProcessingPrompt(
            title: "Meeting Prompt",
            promptText: "meeting",
            isPredefined: false,
        )
        let dictationPrompt = PostProcessingPrompt(
            title: "Dictation Prompt",
            promptText: "dictation",
            isPredefined: false,
        )
        settings.meetingPrompts = [meetingPrompt]
        settings.dictationPrompts = [dictationPrompt]
        settings.selectedPromptId = meetingPrompt.id
        settings.dictationSelectedPromptId = dictationPrompt.id
        settings.updateEnhancementsSelection(provider: .openai, model: "gpt-5.4-mini", for: .meeting)
        settings.updateEnhancementsSelection(provider: .openai, model: "gpt-5.4-mini", for: .dictation)
        settings.postProcessingEnabled = true

        let meeting = CaptureSession(
            app: .importedFile,
            capturePurpose: .dictation,
            audioFilePath: "/tmp/imported-dictation.wav",
        )

        _ = await manager.applyPostProcessing(
            postProcessingInput: "raw dictation text",
            meeting: meeting,
            qualityProfile: nil,
            capturePurposeOverride: .dictation,
        )

        XCTAssertEqual(mockPostProcessing.lastPromptTitle, dictationPrompt.title)
    }

    func testApplyPostProcessing_UsesPersistedPromptWhenCurrentSelectionChanged() async throws {
        let manager = try XCTUnwrap(manager)
        let mockPostProcessing = try XCTUnwrap(mockPostProcessing)
        let settings = AppSettingsStore.shared
        let originalPostProcessingEnabled = settings.postProcessingEnabled
        let originalSelectedPromptID = settings.selectedPromptId
        let originalMeetingPrompts = settings.meetingPrompts
        let originalMeetingSelection = settings.enhancementsAISelection
        let originalProviderModels = settings.enhancementsProviderSelectedModels
        let originalProviderModelsByRegistration = settings.enhancementsProviderSelectedModelsByRegistration
        let currentPrompt = PostProcessingPrompt(title: "Current", promptText: "current")
        let persistedPrompt = PostProcessingPrompt(title: "Persisted", promptText: "persisted")
        defer {
            settings.postProcessingEnabled = originalPostProcessingEnabled
            settings.selectedPromptId = originalSelectedPromptID
            settings.meetingPrompts = originalMeetingPrompts
            settings.enhancementsAISelection = originalMeetingSelection
            settings.enhancementsProviderSelectedModels = originalProviderModels
            settings.enhancementsProviderSelectedModelsByRegistration = originalProviderModelsByRegistration
        }

        settings.postProcessingEnabled = true
        settings.meetingPrompts = [currentPrompt, persistedPrompt]
        settings.selectedPromptId = currentPrompt.id
        settings.updateEnhancementsSelection(provider: .openai, model: "gpt-5.4-mini", for: .meeting)

        _ = await manager.applyPostProcessing(
            postProcessingInput: "meeting text",
            meeting: CaptureSession(app: .zoom, capturePurpose: .meeting),
            qualityProfile: nil,
            capturePurposeOverride: .meeting,
            promptIDOverride: persistedPrompt.id,
        )

        XCTAssertEqual(mockPostProcessing.lastPromptTitle, persistedPrompt.title)
        XCTAssertEqual(mockPostProcessing.lastPromptText, persistedPrompt.promptText)
    }

    func testTranscribeExternalAudio_DoesNotApplySilenceCompaction() async throws {
        let manager = try XCTUnwrap(manager)
        let mockTranscription = try XCTUnwrap(mockTranscription)
        let mockCompactor = try XCTUnwrap(mockAudioSilenceCompactor)
        let settings = AppSettingsStore.shared

        settings.removeSilenceBeforeProcessing = true

        let importedURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        try writeTestAudioFile(at: importedURL)
        defer { try? FileManager.default.removeItem(at: importedURL) }

        await manager.transcribeExternalAudio(from: importedURL)

        XCTAssertEqual(mockTranscription.lastTranscribeAudioURL, importedURL)
        XCTAssertEqual(mockCompactor.compactCallCount, 0)
    }
}

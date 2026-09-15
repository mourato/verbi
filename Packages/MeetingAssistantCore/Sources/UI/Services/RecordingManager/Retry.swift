import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

// swiftlint:disable function_body_length

// MARK: - Retry Transcription

extension RecordingManager {
    /// Retry transcription for an existing entry.
    /// - Parameter transcription: Existing transcription to overwrite with new results.
    /// - Parameter selectionOverride: Optional provider/model override for this retry.
    public func retryTranscription(
        for transcription: Transcription,
        selectionOverride: TranscriptionProviderSelection? = nil
    ) async {
        guard !isTranscribing else {
            AppLogger.info("Already transcribing", category: .recordingManager)
            return
        }

        guard let audioURL = resolveRetryAudioURL(for: transcription) else { return }

        await runRetryTranscription(
            audioURL: audioURL,
            transcription: transcription,
            selectionOverride: selectionOverride
        )
    }

    func resolveRetryAudioURL(for transcription: Transcription) -> URL? {
        guard let audioURL = transcription.audioURL else {
            AppLogger.error("Audio file missing for retry", category: .recordingManager, extra: ["id": transcription.id.uuidString])
            lastError = AudioImportError.fileNotFound
            return nil
        }

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            AppLogger.error("Audio file not found for retry", category: .recordingManager, extra: ["path": audioURL.path])
            lastError = AudioImportError.fileNotFound
            return nil
        }

        return audioURL
    }

    func runRetryTranscription(
        audioURL: URL,
        transcription: Transcription,
        selectionOverride: TranscriptionProviderSelection? = nil
    ) async {
        let capturePurpose = transcription.meeting.capturePurpose
        let retryConfiguration = configuredRetryTranscriptionConfiguration(for: transcription)
        let persistedRequest = transcription.executionProvenance?.transcriptionRequest
        let persistedSelection = persistedRequest.flatMap { request in
            TranscriptionProvider(rawValue: request.providerID).map {
                TranscriptionProviderSelection(provider: $0, selectedModel: request.modelID)
            }
        }
        let postProcessingMode = capturePurpose.intelligenceKernelMode
        let postProcessingSettings = AppSettingsStore.shared
        let postProcessingPromptSnapshot = makePostProcessingPromptSnapshot(
            isDictation: postProcessingMode == .dictation,
            settings: postProcessingSettings
        )
        let persistedPostProcessingSelection = transcription.executionProvenance?.postProcessingSelection.flatMap { selection in
            AIProvider(rawValue: selection.providerID).map {
                EnhancementsAISelection(
                    provider: $0,
                    selectedModel: selection.modelID,
                    registrationID: selection.registrationID
                )
            }
        }
        let capturedPostProcessingSelection = persistedPostProcessingSelection
            ?? postProcessingSettings.enhancementsSelection(for: postProcessingMode)
        let capturedPostProcessingConfiguration = persistedPostProcessingSelection.map {
            postProcessingSettings.resolvedEnhancementsAIConfiguration(for: $0)
        } ?? postProcessingSettings.resolvedEnhancementsAIConfiguration(for: postProcessingMode)
        let capturedPostProcessingReadiness = persistedPostProcessingSelection.map {
            postProcessingSettings.enhancementsInferenceReadinessIssue(
                for: $0,
                apiKeyExists: apiKeyExists
            )
        } ?? postProcessingSettings.enhancementsInferenceReadinessIssue(
            for: postProcessingMode,
            apiKeyExists: apiKeyExists
        )
        let capturedPostProcessingIdentity = transcription.executionProvenance?.postProcessingModelIdentity
            ?? (transcription.executionProvenance == nil
                ? postProcessingSettings.resolvedEnhancementsPerformanceIdentity(for: postProcessingMode)
                : nil)
        let shouldApplyPostProcessing = if let provenance = transcription.executionProvenance {
            provenance.postProcessingModelIdentity != nil
        } else if postProcessingMode == .dictation {
            postProcessingSettings.effectiveDictationStyle(
                bundleIdentifier: transcription.meeting.appBundleIdentifier,
                activeURL: nil
            ).postProcessingEnabled
        } else {
            postProcessingSettings.postProcessingEnabled
        }
        let postProcessingRequestOverrides = PostProcessingRequestOverrides(
            applyPostProcessing: shouldApplyPostProcessing,
            selection: capturedPostProcessingSelection,
            configuration: DomainPostProcessingConfiguration(
                providerID: capturedPostProcessingConfiguration.provider.rawValue,
                baseURL: capturedPostProcessingConfiguration.baseURL,
                modelID: capturedPostProcessingConfiguration.selectedModel,
                readinessIssue: capturedPostProcessingReadiness?.rawValue,
                outputLanguageID: postProcessingMode == .meeting
                    ? postProcessingSettings.meetingSummaryOutputLanguage.rawValue
                    : nil
            ),
            useStructuredPipeline: transcription.executionProvenance?.usedStructuredPostProcessing
                ?? (postProcessingMode == .meeting || postProcessingSettings.dictationStructuredPostProcessingEnabled),
            systemPromptOverride: postProcessingMode == .meeting ? postProcessingSettings.systemPrompt : nil,
            promptSnapshot: postProcessingPromptSnapshot
        )
        let configuredSelection = persistedSelection
            ?? retryConfiguration?.selection
            ?? configuredRetrySelection(for: capturePurpose, meeting: transcription.meeting)
        let effectiveSelection = RetryTranscriptionSelectionMatrix.effectiveSelection(
            requestedOverride: selectionOverride,
            capturePurpose: capturePurpose,
            configuredSelection: configuredSelection,
            transcriptionAPIKeyExists: transcriptionAPIKeyExists,
            isLocalModelReady: isLocalRetryModelReady
        )
        let effectiveSelectionOverride = RetryTranscriptionSelectionMatrix.selectionOverrideIfNeeded(
            requestedOverride: selectionOverride,
            capturePurpose: capturePurpose,
            configuredSelection: configuredSelection,
            transcriptionAPIKeyExists: transcriptionAPIKeyExists,
            isLocalModelReady: isLocalRetryModelReady
        )
        let retryInputLanguageCode = if let persistedRequest {
            persistedRequest.inputLanguageCode
        } else {
            retryConfiguration?.inputLanguageCode
                ?? AppSettingsStore.shared.resolvedTranscriptionInputLanguageCode(
                    for: capturePurpose.transcriptionExecutionMode
                )
        }
        let vocabularySnapshot = selectionOverride == nil
            ? transcription.executionProvenance?.vocabularySnapshot ?? VocabularySnapshot.current(from: .shared)
            : VocabularySnapshot.current(from: .shared)
        let capturedConfiguration = DomainTranscriptionRequestConfiguration(
            providerID: effectiveSelection.provider.rawValue,
            modelID: effectiveSelection.selectedModel,
            inputLanguageCode: retryInputLanguageCode,
            vocabularyHints: vocabularySnapshot.providerHints.isEmpty ? nil : vocabularySnapshot.providerHints
        )
        let shouldRemoveSilence = shouldRemoveSilenceBeforeRetryTranscription(
            effectiveSelection: effectiveSelection
        )
        let preparedAudio = await prepareAudioForTranscription(
            audioURL: audioURL,
            allowSilenceRemoval: shouldRemoveSilence
        )
        defer {
            cleanupPreparedTranscriptionAudio(preparedAudio)
        }

        isTranscribing = true
        cancelEstimatedPostProcessingProgress()
        let audioDuration = await getAudioDuration(from: preparedAudio.transcriptionURL)
        transcriptionStatus.beginTranscription(audioDuration: audioDuration)
        RecordingIndicatorProcessingStateStore.shared.update(
            snapshot: RecordingIndicatorProcessingSnapshot(step: .preparingAudio, progressPercent: 0)
        )

        let retryStartedAt = Date()
        do {
            let updated = try await performRetryTranscription(
                audioURL: preparedAudio.transcriptionURL,
                transcription: transcription,
                audioDuration: audioDuration,
                selectionOverride: effectiveSelectionOverride ?? effectiveSelection,
                effectiveSelection: effectiveSelection,
                inputLanguageCode: retryInputLanguageCode,
                transcriptionConfiguration: capturedConfiguration,
                vocabularySnapshot: vocabularySnapshot,
                postProcessingRequestOverrides: postProcessingRequestOverrides,
                postProcessingIdentity: capturedPostProcessingIdentity
            )
            try await storage.saveTranscription(updated)
            await persistRetryPerformanceAttempts(
                updatedTranscription: updated,
                effectiveSelection: effectiveSelection,
                startedAt: retryStartedAt,
                completedAt: Date()
            )
            RecordingIndicatorProcessingStateStore.shared.update(
                snapshot: RecordingIndicatorProcessingSnapshot(step: .finalizingResult, progressPercent: 100)
            )
            transcriptionStatus.completeTranscription(success: true)
            notifySuccess(for: updated)
            scheduleStatusReset()
        } catch {
            await persistFailedRetryPerformanceAttempt(
                transcription: transcription,
                effectiveSelection: effectiveSelection,
                transcriptionConfiguration: capturedConfiguration,
                vocabularySnapshot: vocabularySnapshot,
                startedAt: retryStartedAt,
                completedAt: Date(),
                audioDuration: audioDuration,
                error: error
            )
            cancelEstimatedPostProcessingProgress()
            handleTranscriptionError(error)
        }

        cancelEstimatedPostProcessingProgress()
        isTranscribing = false
    }

    func performRetryTranscription(
        audioURL: URL,
        transcription: Transcription,
        audioDuration: Double?,
        selectionOverride: TranscriptionProviderSelection? = nil,
        effectiveSelection: TranscriptionProviderSelection,
        inputLanguageCode: String? = nil,
        transcriptionConfiguration: DomainTranscriptionRequestConfiguration? = nil,
        vocabularySnapshot: VocabularySnapshot? = nil,
        postProcessingRequestOverrides: PostProcessingRequestOverrides? = nil,
        postProcessingIdentity: ModelPerformanceModelIdentity? = nil
    ) async throws -> Transcription {
        try await performHealthCheck(
            capturePurpose: transcription.meeting.capturePurpose,
            effectiveSelection: effectiveSelection
        )

        let vocabularySnapshot = vocabularySnapshot ?? VocabularySnapshot.current(from: .shared)
        let transcriptionStart = Date()
        let response = try await performTranscription(
            audioURL: audioURL,
            diarizationEnabledOverride: shouldEnableDiarization(for: transcription.meeting),
            capturePurpose: transcription.meeting.capturePurpose,
            selectionOverride: selectionOverride ?? effectiveSelection,
            inputLanguageCode: inputLanguageCode,
            vocabularyHints: vocabularySnapshot.providerHints.isEmpty ? nil : vocabularySnapshot.providerHints,
            transcriptionConfiguration: transcriptionConfiguration
        )
        let transcriptionProcessingDuration = Date().timeIntervalSince(transcriptionStart)
        let replacedText = VocabularyReplacementRule.apply(
            rules: vocabularySnapshot.replacementRules,
            to: response.text
        )
        guard !replacedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranscriptionError.transcriptionFailed(
                PostProcessingError.emptyTranscription.localizedDescription
            )
        }
        let wordCount = replacedText.split { $0.isWhitespace || $0.isNewline }.count
        AppLogger.info(
            "Validated transcript before post-processing",
            category: .recordingManager,
            extra: [
                "characters": String(replacedText.trimmingCharacters(in: .whitespacesAndNewlines).count),
                "words": String(wordCount),
                "segments": String(response.segments.count),
                "durationSeconds": String(response.durationSeconds)
            ]
        )
        let replacedSegments = VocabularyReplacementRule.apply(
            rules: vocabularySnapshot.replacementRules,
            to: response.segments
        )
        let qualityProfile = transcriptPreprocessor.preprocess(
            transcriptionText: replacedText,
            segments: replacedSegments.map {
                DomainTranscriptionSegment(
                    id: $0.id,
                    speaker: $0.speaker,
                    text: $0.text,
                    startTime: $0.startTime,
                    endTime: $0.endTime
                )
            },
            asrConfidenceScore: response.confidenceScore
        )
        let includeQualityMetadata = !isDictationMode(
            for: transcription.meeting,
            capturePurposeOverride: transcription.meeting.capturePurpose
        )
        let contextWithVocabulary = vocabularySnapshot.prependToContext(postProcessingContext)
        let resolvedPostProcessingContext = PostProcessingSystemContextMetadata.augment(contextWithVocabulary)
        let postProcessingInput = PostProcessingInputComposer.compose(
            transcriptionText: qualityProfile.normalizedTextForIntelligence,
            qualityProfile: qualityProfile,
            context: resolvedPostProcessingContext,
            meetingNotes: transcription.contextItems.first(where: { $0.source == .meetingNotes })?.text,
            includeQualityMetadata: includeQualityMetadata
        )

        let persistedPostProcessingSelection = transcription.executionProvenance?.postProcessingSelection.flatMap { selection in
            AIProvider(rawValue: selection.providerID).map {
                EnhancementsAISelection(
                    provider: $0,
                    selectedModel: selection.modelID,
                    registrationID: selection.registrationID
                )
            }
        }
        let meeting = updatedMeeting(for: transcription.meeting, audioDuration: audioDuration)
        let postProcessing = await applyPostProcessing(
            postProcessingInput: postProcessingInput,
            meeting: meeting,
            qualityProfile: qualityProfile,
            capturePurposeOverride: transcription.meeting.capturePurpose,
            selectionOverride: persistedPostProcessingSelection,
            promptIDOverride: transcription.executionProvenance?.postProcessingPromptID,
            requestOverrides: postProcessingRequestOverrides
        )
        let resolvedMeeting = meetingWithResolvedTitle(meeting, canonicalSummary: postProcessing.canonicalSummary)
        let retryPostProcessingSelection = transcription.executionProvenance?.postProcessingSelection
            ?? postProcessingRequestOverrides.map {
                DomainPostProcessingSelection(
                    providerID: $0.selection.provider.rawValue,
                    modelID: $0.selection.selectedModel,
                    registrationID: $0.selection.registrationID
                )
            }
        let postProcessingMode = transcription.capturePurpose.intelligenceKernelMode

        return Transcription(
            id: transcription.id,
            meeting: resolvedMeeting,
            contextItems: transcription.contextItems,
            segments: replacedSegments,
            text: postProcessing.processedContent ?? replacedText,
            rawText: response.text,
            processedContent: postProcessing.processedContent,
            canonicalSummary: postProcessing.canonicalSummary,
            qualityProfile: qualityProfile,
            postProcessingPromptId: postProcessing.promptId,
            postProcessingPromptTitle: postProcessing.promptTitle,
            postProcessingRequestSystemPrompt: postProcessing.requestSystemPrompt,
            postProcessingRequestUserPrompt: postProcessing.requestUserPrompt,
            language: response.language,
            createdAt: transcription.createdAt,
            modelName: response.model,
            inputSource: transcription.inputSource,
            transcriptionDuration: transcriptionProcessingDuration,
            postProcessingDuration: postProcessing.duration,
            postProcessingModel: postProcessing.model,
            meetingType: transcription.meeting.type.rawValue,
            postProcessingFailureReason: postProcessing.failureReason,
            postProcessingOutputState: postProcessing.outputState,
            transcriptionFailureReason: nil,
            executionProvenance: ExecutionProvenance(
                transcriptionRequest: transcriptionConfiguration ?? transcription.executionProvenance?.transcriptionRequest,
                vocabularySnapshot: vocabularySnapshot,
                transcriptionModelIdentity: effectiveSelection.provider.modelPerformanceIdentity(modelID: effectiveSelection.selectedModel),
                postProcessingSelection: retryPostProcessingSelection,
                postProcessingModelIdentity: postProcessingIdentity,
                postProcessingPromptID: postProcessing.promptId ?? transcription.executionProvenance?.postProcessingPromptID,
                postProcessingPromptTitle: postProcessing.promptTitle ?? transcription.executionProvenance?.postProcessingPromptTitle,
                kernelMode: postProcessingMode,
                usedStructuredPostProcessing: postProcessingRequestOverrides.map {
                    $0.applyPostProcessing && $0.useStructuredPipeline
                }
            )
        )
    }

    func shouldRemoveSilenceBeforeRetryTranscription(
        effectiveSelection: TranscriptionProviderSelection
    ) -> Bool {
        !effectiveSelection.provider.usesRemoteInference
    }

    private func persistRetryPerformanceAttempts(
        updatedTranscription: Transcription,
        effectiveSelection: TranscriptionProviderSelection,
        startedAt: Date,
        completedAt: Date
    ) async {
        let transcriptionIdentity = effectiveSelection.provider.modelPerformanceIdentity(
            modelID: effectiveSelection.selectedModel
        )
        let transcriptionAttempt = ModelPerformanceAttempt(
            transcriptionID: updatedTranscription.id,
            stage: .transcription,
            attemptKind: .retry,
            capturePurpose: updatedTranscription.capturePurpose,
            modelIdentity: transcriptionIdentity,
            status: .succeeded,
            startedAt: startedAt,
            completedAt: completedAt,
            wallClockSeconds: updatedTranscription.transcriptionDuration,
            audioSeconds: max(0, updatedTranscription.meeting.duration),
            inputUTF8Bytes: 0,
            inputCharacterCount: 0,
            outputCharacterCount: updatedTranscription.rawText.count,
            failureReason: nil,
            executionProvenance: updatedTranscription.executionProvenance
        )
        try? await storage.saveModelPerformanceAttempt(transcriptionAttempt)

        guard updatedTranscription.postProcessingDuration > 0 || updatedTranscription.postProcessingModel != nil else {
            return
        }

        guard let postProcessingIdentity = updatedTranscription.executionProvenance?.postProcessingModelIdentity else {
            return
        }
        let postProcessingAttempt = ModelPerformanceAttempt(
            transcriptionID: updatedTranscription.id,
            stage: .postProcessing,
            attemptKind: .retry,
            capturePurpose: updatedTranscription.capturePurpose,
            modelIdentity: postProcessingIdentity,
            status: updatedTranscription.processedContent == nil ? .failed : .succeeded,
            startedAt: completedAt.addingTimeInterval(-max(0, updatedTranscription.postProcessingDuration)),
            completedAt: completedAt,
            wallClockSeconds: updatedTranscription.postProcessingDuration,
            audioSeconds: 0,
            inputUTF8Bytes: updatedTranscription.rawText.lengthOfBytes(using: .utf8),
            inputCharacterCount: updatedTranscription.rawText.count,
            outputCharacterCount: updatedTranscription.processedContent?.count ?? 0,
            failureReason: updatedTranscription.postProcessingFailureReason,
            executionProvenance: updatedTranscription.executionProvenance
        )
        try? await storage.saveModelPerformanceAttempt(postProcessingAttempt)
    }

    // swiftlint:disable:next function_parameter_count
    private func persistFailedRetryPerformanceAttempt(
        transcription: Transcription,
        effectiveSelection: TranscriptionProviderSelection,
        transcriptionConfiguration: DomainTranscriptionRequestConfiguration,
        vocabularySnapshot: VocabularySnapshot,
        startedAt: Date,
        completedAt: Date,
        audioDuration: Double?,
        error: Error
    ) async {
        let identity = effectiveSelection.provider.modelPerformanceIdentity(
            modelID: effectiveSelection.selectedModel
        )
        let attempt = ModelPerformanceAttempt(
            transcriptionID: transcription.id,
            stage: .transcription,
            attemptKind: .retry,
            capturePurpose: transcription.capturePurpose,
            modelIdentity: identity,
            status: .failed,
            startedAt: startedAt,
            completedAt: completedAt,
            wallClockSeconds: max(0, completedAt.timeIntervalSince(startedAt)),
            audioSeconds: max(0, audioDuration ?? transcription.meeting.duration),
            inputUTF8Bytes: 0,
            inputCharacterCount: 0,
            outputCharacterCount: 0,
            failureReason: error.localizedDescription,
            executionProvenance: ExecutionProvenance(
                transcriptionRequest: transcriptionConfiguration,
                vocabularySnapshot: vocabularySnapshot,
                transcriptionModelIdentity: identity
            )
        )
        try? await storage.saveModelPerformanceAttempt(attempt)
    }

    private func configuredRetrySelection(
        for capturePurpose: CapturePurpose,
        meeting: Meeting
    ) -> TranscriptionProviderSelection {
        if capturePurpose == .dictation {
            return AppSettingsStore.shared.effectiveDictationStyle(
                bundleIdentifier: meeting.appBundleIdentifier,
                activeURL: nil
            ).transcriptionConfiguration.selection
        }

        return AppSettingsStore.shared.resolvedTranscriptionSelection(for: .meeting)
    }

    private func configuredRetryTranscriptionConfiguration(
        for transcription: Transcription
    ) -> DictationTranscriptionConfiguration? {
        guard transcription.meeting.capturePurpose == .dictation else { return nil }
        return AppSettingsStore.shared.effectiveDictationStyle(
            bundleIdentifier: transcription.meeting.appBundleIdentifier,
            activeURL: nil
        ).transcriptionConfiguration
    }

    // MARK: - Post Processing Input

    func recalibrateCanonicalSummary(
        _ summary: CanonicalSummary,
        with qualityProfile: TranscriptionQualityProfile
    ) -> CanonicalSummary {
        let trustFlags = CanonicalSummary.TrustFlags(
            isGroundedInTranscript: summary.trustFlags.isGroundedInTranscript,
            containsSpeculation: summary.trustFlags.containsSpeculation || qualityProfile.containsUncertainty,
            isHumanReviewed: summary.trustFlags.isHumanReviewed,
            confidenceScore: min(summary.trustFlags.confidenceScore, qualityProfile.overallConfidence)
        )

        return CanonicalSummary(
            schemaVersion: summary.schemaVersion,
            generatedAt: summary.generatedAt,
            title: summary.title,
            summary: summary.summary,
            keyPoints: summary.keyPoints,
            decisions: summary.decisions,
            actionItems: summary.actionItems,
            openQuestions: summary.openQuestions,
            trustFlags: trustFlags
        )
    }

    func meetingWithResolvedTitle(
        _ meeting: Meeting,
        canonicalSummary: CanonicalSummary?
    ) -> Meeting {
        guard meeting.supportsMeetingConversation else {
            return meeting.sanitizedForPersistence()
        }

        guard let title = canonicalSummary?.title.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return meeting
        }

        if let persistedTitle = meeting.title?.trimmingCharacters(in: .whitespacesAndNewlines), !persistedTitle.isEmpty {
            return meeting
        }

        if let calendarTitle = meeting.linkedCalendarEvent?.trimmedTitle, !calendarTitle.isEmpty {
            return meeting
        }

        var updatedMeeting = meeting
        updatedMeeting.title = title
        return updatedMeeting
    }

    func updatedMeeting(for meeting: Meeting, audioDuration: Double?) -> Meeting {
        guard let audioDuration else { return meeting }
        guard meeting.endTime == nil else { return meeting }

        var updatedMeeting = meeting
        updatedMeeting.endTime = meeting.startTime.addingTimeInterval(audioDuration)
        return updatedMeeting
    }

    func resolveInputSourceLabel(
        for meeting: Meeting,
        recordingSource: RecordingSource? = nil
    ) -> String? {
        if meeting.app == .importedFile {
            return "meeting.app.imported".localized
        }

        switch recordingSource ?? self.recordingSource {
        case .microphone:
            return resolveMicrophoneDeviceName() ?? "recording.source.microphone".localized
        case .system:
            return "recording.source.system".localized
        case .all:
            let system = "recording.source.system".localized
            let mic = resolveMicrophoneDeviceName()
            if let mic {
                return "\(system) + \(mic)"
            }
            let microphone = "recording.source.microphone".localized
            return "\(system) + \(microphone)"
        }
    }

    func resolveMicrophoneDeviceName() -> String? {
        let settings = AppSettingsStore.shared

        return microphoneInputSelectionResolver.resolvePreferredMicrophoneDeviceName(settings: settings)
    }

    func resolveSystemDefaultMicrophoneDeviceName() -> String? {
        microphoneInputSelectionResolver.resolveSystemDefaultMicrophoneDeviceName()
    }
}

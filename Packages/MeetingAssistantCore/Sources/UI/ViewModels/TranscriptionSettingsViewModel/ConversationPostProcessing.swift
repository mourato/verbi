import AppKit
import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import OSLog
import SwiftUI

public extension TranscriptionSettingsViewModel {
    func isPostProcessing(transcriptionID: UUID) -> Bool {
        postProcessingByTranscriptionID.contains(transcriptionID)
    }

    func postProcessingError(for transcriptionID: UUID) -> String? {
        postProcessingErrorByTranscriptionID[transcriptionID]
    }

    var availablePrompts: [PostProcessingPrompt] {
        settings.allPrompts
    }

    func availablePrompts(for metadata: TranscriptionMetadata) -> [PostProcessingPrompt] {
        if !metadata.supportsMeetingConversation {
            return settings.dictationAvailablePrompts
        }
        return settings.meetingAvailablePrompts
    }

    func availableRetryTranscriptionOptions(for metadata: TranscriptionMetadata) -> [RetryTranscriptionOption] {
        RetryTranscriptionSelectionMatrix.eligibleSelections(
            for: metadata.capturePurpose,
            transcriptionAPIKeyExists: { [keychain] provider in
                keychain.existsTranscriptionAPIKey(for: provider)
            },
            isLocalModelReady: isLocalModelReady
        )
        .map(RetryTranscriptionOption.init)
    }

    func applyPostProcessing(prompt: PostProcessingPrompt, transcriptionID: UUID) async {
        do {
            if let selected = selectedTranscription, selected.id == transcriptionID {
                await applyPostProcessing(prompt: prompt, to: selected)
                return
            }

            guard let loaded = try await storage.loadTranscription(by: transcriptionID) else {
                operationErrorMessage = "transcription.post_processing.error".localized
                return
            }
            selectedTranscription = loaded
            selectedId = transcriptionID
            await applyPostProcessing(prompt: prompt, to: loaded)
        } catch {
            operationErrorMessage = error.localizedDescription
        }
    }

    // swiftlint:disable:next function_body_length
    func applyPostProcessing(prompt: PostProcessingPrompt, to transcription: Transcription) async {
        guard !isProcessingAI else { return }

        let transcriptionID = transcription.id
        markPostProcessingStarted(for: transcriptionID)
        let startTime = Date()
        let mode: IntelligenceKernelMode = transcription.capturePurpose.intelligenceKernelMode
        let postProcessingSelection = settings.enhancementsSelection(for: mode)
        let postProcessingIdentity = settings.resolvedEnhancementsPerformanceIdentity(for: mode)
        let useStructuredPipeline = mode == .meeting || settings.dictationStructuredPostProcessingEnabled
        let postProcessingConfiguration = settings.resolvedEnhancementsAIConfiguration(for: postProcessingSelection)
        let readinessIssue = settings.enhancementsInferenceReadinessIssue(for: postProcessingSelection, apiKeyExists: nil)
        let request = DomainPostProcessingRequest(
            prompt: DomainPostProcessingPrompt(id: prompt.id, title: prompt.title, content: prompt.promptText),
            mode: mode,
            selection: DomainPostProcessingSelection(
                providerID: postProcessingSelection.provider.rawValue,
                modelID: postProcessingSelection.selectedModel,
                registrationID: postProcessingSelection.registrationID
            ),
            configuration: DomainPostProcessingConfiguration(
                providerID: postProcessingConfiguration.provider.rawValue,
                baseURL: postProcessingConfiguration.baseURL,
                modelID: postProcessingConfiguration.selectedModel,
                readinessIssue: readinessIssue?.rawValue,
                outputLanguageID: mode == .meeting ? settings.meetingSummaryOutputLanguage.rawValue : nil
            ),
            useStructuredPipeline: useStructuredPipeline,
            systemPromptOverride: mode == .meeting ? settings.systemPrompt : nil
        )
        let executionProvenance = makeReprocessProvenance(
            transcription: transcription,
            prompt: prompt,
            selection: postProcessingSelection,
            identity: postProcessingIdentity,
            mode: mode,
            useStructuredPipeline: useStructuredPipeline
        )
        let postProcessingInput = postProcessingInput(for: transcription)
        defer { markPostProcessingFinished(for: transcriptionID) }

        do {
            let result = try await runPostProcessing(
                postProcessingInput: postProcessingInput,
                request: request
            )
            let duration = Date().timeIntervalSince(startTime)
            let modelUsed = postProcessingSelection.selectedModel
            let updatedTranscription = makePostProcessedTranscription(
                from: transcription,
                prompt: prompt,
                processedText: result.processedText,
                canonicalSummary: result.canonicalSummary,
                outputState: result.outputState,
                duration: duration,
                modelUsed: modelUsed,
                executionProvenance: executionProvenance
            )

            try await storage.saveTranscription(updatedTranscription)
            try? await storage.saveModelPerformanceAttempt(
                makeReprocessAttempt(
                    transcription: transcription,
                    identity: postProcessingIdentity,
                    status: .succeeded,
                    startedAt: startTime,
                    completedAt: Date(),
                    input: postProcessingInput,
                    outputCharacterCount: result.processedText.count,
                    failureReason: nil,
                    executionProvenance: executionProvenance
                )
            )

            selectedTranscription = updatedTranscription
            clearPostProcessingError(for: transcriptionID)
            await loadTranscriptions()
        } catch {
            await handlePostProcessingFailure(
                error: error,
                transcription: transcription,
                transcriptionID: transcriptionID,
                identity: postProcessingIdentity,
                startedAt: startTime,
                input: postProcessingInput,
                executionProvenance: executionProvenance
            )
        }
    }

    private struct ReprocessPipelineResult {
        let processedText: String
        let canonicalSummary: CanonicalSummary?
        let outputState: DomainPostProcessingOutputState?
    }

    private func runPostProcessing(
        postProcessingInput: String,
        request: DomainPostProcessingRequest
    ) async throws -> ReprocessPipelineResult {
        if request.useStructuredPipeline {
            let structuredResult = try await recordingManager.postProcessingRepository.processTranscriptionStructured(
                postProcessingInput,
                request: request
            )
            return ReprocessPipelineResult(
                processedText: structuredResult.processedText,
                canonicalSummary: structuredResult.canonicalSummary,
                outputState: structuredResult.outputState
            )
        }

        let processedText = try await recordingManager.postProcessingRepository.processTranscription(
            postProcessingInput,
            request: request
        )
        return ReprocessPipelineResult(
            processedText: processedText,
            canonicalSummary: nil,
            outputState: nil
        )
    }

    // swiftlint:disable:next function_parameter_count
    private func makeReprocessAttempt(
        transcription: Transcription,
        identity: ModelPerformanceModelIdentity,
        status: ModelPerformanceAttemptStatus,
        startedAt: Date,
        completedAt: Date,
        input: String,
        outputCharacterCount: Int,
        failureReason: String?,
        executionProvenance: ExecutionProvenance
    ) -> ModelPerformanceAttempt {
        ModelPerformanceAttempt(
            transcriptionID: transcription.id,
            stage: .postProcessing,
            attemptKind: .reprocess,
            capturePurpose: transcription.capturePurpose,
            modelIdentity: identity,
            status: status,
            startedAt: startedAt,
            completedAt: completedAt,
            wallClockSeconds: max(0, completedAt.timeIntervalSince(startedAt)),
            audioSeconds: 0,
            inputUTF8Bytes: input.lengthOfBytes(using: .utf8),
            inputCharacterCount: input.count,
            outputCharacterCount: outputCharacterCount,
            failureReason: failureReason,
            executionProvenance: executionProvenance
        )
    }

    // swiftlint:disable:next function_parameter_count
    private func handlePostProcessingFailure(
        error: Error,
        transcription: Transcription,
        transcriptionID: UUID,
        identity: ModelPerformanceModelIdentity,
        startedAt: Date,
        input: String,
        executionProvenance: ExecutionProvenance
    ) async {
        let message: String
        if let processingError = error as? PostProcessingError {
            logger.error("Failed to apply post-processing: \(processingError.localizedDescription)")
            message = processingError.localizedDescription
        } else {
            logger.error("Failed to apply post-processing: \(error.localizedDescription)")
            message = "transcription.post_processing.error".localized
        }

        try? await storage.saveModelPerformanceAttempt(
            makeReprocessAttempt(
                transcription: transcription,
                identity: identity,
                status: .failed,
                startedAt: startedAt,
                completedAt: Date(),
                input: input,
                outputCharacterCount: 0,
                failureReason: message,
                executionProvenance: executionProvenance
            )
        )
        var failedTranscription = transcription
        failedTranscription.postProcessingFailureReason = message
        do {
            try await storage.saveTranscription(failedTranscription)
        } catch {
            logger.error("Failed to persist post-processing failure on transcription: \(error.localizedDescription)")
        }
        selectedTranscription = failedTranscription
        await loadTranscriptions()
        postProcessingErrorByTranscriptionID[transcriptionID] = message
        operationErrorMessage = message
    }

    // swiftlint:disable:next function_parameter_count
    private func makePostProcessedTranscription(
        from transcription: Transcription,
        prompt: PostProcessingPrompt,
        processedText: String,
        canonicalSummary: CanonicalSummary?,
        outputState: DomainPostProcessingOutputState?,
        duration: TimeInterval,
        modelUsed: String,
        executionProvenance: ExecutionProvenance
    ) -> Transcription {
        Transcription(
            id: transcription.id,
            meeting: transcription.meeting,
            contextItems: transcription.contextItems,
            segments: sortedSegments(transcription.segments),
            text: processedText,
            rawText: transcription.rawText,
            processedContent: processedText,
            canonicalSummary: canonicalSummary,
            qualityProfile: transcription.qualityProfile,
            postProcessingPromptId: prompt.id,
            postProcessingPromptTitle: prompt.title,
            language: transcription.language,
            createdAt: transcription.createdAt,
            modelName: transcription.modelName,
            inputSource: transcription.inputSource,
            transcriptionDuration: transcription.transcriptionDuration,
            postProcessingDuration: duration,
            postProcessingModel: modelUsed,
            meetingType: transcription.meetingType,
            meetingConversationState: transcription.meetingConversationState,
            postProcessingFailureReason: nil,
            postProcessingOutputState: outputState,
            transcriptionFailureReason: transcription.transcriptionFailureReason,
            executionProvenance: executionProvenance
        )
    }

    // swiftlint:disable:next function_parameter_count
    private func makeReprocessProvenance(
        transcription: Transcription,
        prompt: PostProcessingPrompt,
        selection: EnhancementsAISelection,
        identity: ModelPerformanceModelIdentity,
        mode: IntelligenceKernelMode,
        useStructuredPipeline: Bool
    ) -> ExecutionProvenance {
        ExecutionProvenance(
            transcriptionRequest: transcription.executionProvenance?.transcriptionRequest,
            vocabularySnapshot: transcription.executionProvenance?.vocabularySnapshot ?? .empty,
            transcriptionModelIdentity: transcription.executionProvenance?.transcriptionModelIdentity
                ?? ModelPerformanceModelIdentity(
                    providerID: "unknown",
                    providerDisplayName: "Unknown",
                    modelID: "unknown",
                    modelDisplayName: "Unknown",
                    runtimeKind: .unknown
                ),
            postProcessingSelection: DomainPostProcessingSelection(
                providerID: selection.provider.rawValue,
                modelID: selection.selectedModel,
                registrationID: selection.registrationID
            ),
            postProcessingModelIdentity: identity,
            postProcessingPromptID: prompt.id,
            postProcessingPromptTitle: prompt.title,
            kernelMode: mode,
            usedStructuredPostProcessing: useStructuredPipeline
        )
    }

    private func postProcessingInput(for transcription: Transcription) -> String {
        let segments = sortedSegments(transcription.segments)
        guard !segments.isEmpty else {
            return transcription.rawText
        }

        return segments
            .map { segment in
                "[\(segment.startTime)-\(segment.endTime)] \(segment.speaker): \(segment.text)"
            }
            .joined(separator: "\n")
    }

    private func markPostProcessingStarted(for transcriptionID: UUID) {
        postProcessingByTranscriptionID.insert(transcriptionID)
        isProcessingAI = !postProcessingByTranscriptionID.isEmpty
    }

    private func markPostProcessingFinished(for transcriptionID: UUID) {
        postProcessingByTranscriptionID.remove(transcriptionID)
        isProcessingAI = !postProcessingByTranscriptionID.isEmpty
    }

    private func clearPostProcessingError(for transcriptionID: UUID) {
        postProcessingErrorByTranscriptionID.removeValue(forKey: transcriptionID)
    }
}

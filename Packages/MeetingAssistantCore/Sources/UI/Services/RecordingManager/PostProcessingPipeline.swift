import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

// MARK: - Post Processing Pipeline

extension RecordingManager {
    struct PostProcessingPromptSnapshot {
        let availablePrompts: [PostProcessingPrompt]
        let selectedPrompt: PostProcessingPrompt
    }

    struct PostProcessingRequestOverrides {
        let applyPostProcessing: Bool
        let selection: EnhancementsAISelection
        let configuration: DomainPostProcessingConfiguration
        let useStructuredPipeline: Bool
        let systemPromptOverride: String?
        let promptSnapshot: PostProcessingPromptSnapshot
    }

    struct PostProcessingResult {
        let processedContent: String?
        let canonicalSummary: CanonicalSummary?
        let promptId: UUID?
        let promptTitle: String?
        let duration: Double
        let model: String?
        let requestSystemPrompt: String?
        let requestUserPrompt: String?
        let failureReason: String?
        let outputState: DomainPostProcessingOutputState?

        static var empty: PostProcessingResult {
            PostProcessingResult(
                processedContent: nil,
                canonicalSummary: nil,
                promptId: nil,
                promptTitle: nil,
                duration: 0,
                model: nil,
                requestSystemPrompt: nil,
                requestUserPrompt: nil,
                failureReason: nil,
                outputState: nil
            )
        }

        init(
            processedContent: String? = nil,
            canonicalSummary: CanonicalSummary? = nil,
            promptId: UUID? = nil,
            promptTitle: String? = nil,
            duration: Double = 0,
            model: String? = nil,
            requestSystemPrompt: String? = nil,
            requestUserPrompt: String? = nil,
            failureReason: String? = nil,
            outputState: DomainPostProcessingOutputState? = nil
        ) {
            self.processedContent = processedContent
            self.canonicalSummary = canonicalSummary
            self.promptId = promptId
            self.promptTitle = promptTitle
            self.duration = duration
            self.model = model
            self.requestSystemPrompt = requestSystemPrompt
            self.requestUserPrompt = requestUserPrompt
            self.failureReason = failureReason
            self.outputState = outputState
        }
    }

    private struct PostProcessingExecution {
        let processedContent: String
        let canonicalSummary: CanonicalSummary?
        let outputState: DomainPostProcessingOutputState?
    }

    // swiftlint:disable:next function_body_length
    func applyPostProcessing(
        postProcessingInput: String,
        meeting: Meeting?,
        qualityProfile: TranscriptionQualityProfile?,
        capturePurposeOverride: CapturePurpose? = nil,
        selectionOverride: EnhancementsAISelection? = nil,
        promptIDOverride: UUID? = nil,
        requestOverrides: PostProcessingRequestOverrides? = nil
    ) async -> PostProcessingResult {
        transcriptionStatus.updateProgress(phase: .postProcessing, percentage: Constants.postProcessingProgress)
        RecordingIndicatorProcessingStateStore.shared.update(
            snapshot: RecordingIndicatorProcessingSnapshot(
                step: .postProcessing,
                progressPercent: Constants.postProcessingProgress
            )
        )

        let settings = AppSettingsStore.shared
        let kernelMode = postProcessingKernelMode(
            for: meeting,
            capturePurposeOverride: capturePurposeOverride
        )
        let isDictation = kernelMode == .dictation
        let shouldApplyPostProcessing = requestOverrides?.applyPostProcessing
            ?? (isDictation || settings.postProcessingEnabled)
        guard shouldApplyPostProcessing else {
            return PostProcessingResult(failureReason: "Post-processing is disabled globally.")
        }
        guard requestOverrides != nil || !isDictation || (matchingDictationStyleForDictation(settings: settings)?.postProcessingEnabled ?? true) else {
            return PostProcessingResult(failureReason: "Post-processing is disabled for this recording type.")
        }
        let requestSelectionOverride = requestOverrides?.selection ?? selectionOverride ?? (isDictation
            ? matchingDictationStyleForDictation(settings: settings)?.enhancementsSelection
            : nil)
        let readinessIssue = requestOverrides == nil
            ? (requestSelectionOverride.map {
                settings.enhancementsInferenceReadinessIssue(for: $0, apiKeyExists: apiKeyExists)
            } ?? settings.enhancementsInferenceReadinessIssue(for: kernelMode, apiKeyExists: apiKeyExists))
            : nil
        setPostProcessingReadinessWarning(issue: readinessIssue, mode: kernelMode)
        if let readinessIssue {
            let reasonCode = readinessIssue.rawValue
            AppLogger.info(
                "Post-processing skipped: enhancements configuration not ready",
                category: .recordingManager,
                extra: ["reasonCode": reasonCode]
            )
            return PostProcessingResult(failureReason: postProcessingFailureReason(for: readinessIssue))
        }

        let requestSelection = requestSelectionOverride ?? settings.enhancementsSelection(for: kernelMode)
        let requestConfiguration = requestOverrides?.configuration ?? {
            let configuration = requestSelectionOverride == nil
                ? settings.resolvedEnhancementsAIConfiguration(for: kernelMode)
                : settings.resolvedEnhancementsAIConfiguration(for: requestSelection)
            return DomainPostProcessingConfiguration(
                providerID: configuration.provider.rawValue,
                baseURL: configuration.baseURL,
                modelID: configuration.selectedModel,
                readinessIssue: readinessIssue?.rawValue,
                outputLanguageID: kernelMode == .meeting ? settings.meetingSummaryOutputLanguage.rawValue : nil
            )
        }()
        let useStructuredPipeline = requestOverrides?.useStructuredPipeline
            ?? (kernelMode == .meeting || settings.dictationStructuredPostProcessingEnabled)
        let systemPromptOverride = requestOverrides.map(\.systemPromptOverride)
            ?? (kernelMode == .meeting ? settings.systemPrompt : nil)
        let promptSnapshot = requestOverrides?.promptSnapshot
            ?? makePostProcessingPromptSnapshot(isDictation: isDictation, settings: settings)
        let requestContext = DomainPostProcessingRequest(
            mode: kernelMode,
            selection: DomainPostProcessingSelection(
                providerID: requestSelection.provider.rawValue,
                modelID: requestSelection.selectedModel,
                registrationID: requestSelection.registrationID
            ),
            configuration: requestConfiguration,
            useStructuredPipeline: useStructuredPipeline,
            systemPromptOverride: systemPromptOverride
        )

        let type = meeting?.type ?? currentMeeting?.type ?? .general
        if type == .autodetect {
            RecordingIndicatorProcessingStateStore.shared.update(
                snapshot: RecordingIndicatorProcessingSnapshot(
                    step: .detectingMeetingType,
                    progressPercent: Constants.postProcessingProgress
                )
            )
        }
        let prompt = if let promptIDOverride,
                        let persistedPrompt = promptSnapshot.availablePrompts.first(where: { $0.id == promptIDOverride })
        {
            persistedPrompt
        } else {
            await resolvePostProcessingPrompt(
                rawText: TranscriptionOutputSanitizer.stripPromptMetadata(from: postProcessingInput),
                isDictation: isDictation,
                meetingType: type,
                snapshot: promptSnapshot,
                request: requestContext
            )
        }

        let request = DomainPostProcessingRequest(
            prompt: DomainPostProcessingPrompt(id: prompt.id, title: prompt.title, content: prompt.promptText),
            mode: kernelMode,
            selection: DomainPostProcessingSelection(
                providerID: requestSelection.provider.rawValue,
                modelID: requestSelection.selectedModel,
                registrationID: requestSelection.registrationID
            ),
            configuration: requestConfiguration,
            useStructuredPipeline: useStructuredPipeline,
            systemPromptOverride: systemPromptOverride
        )

        transcriptionStatus.updateProgress(phase: .postProcessing, percentage: Constants.aiProcessingProgress)
        RecordingIndicatorProcessingStateStore.shared.update(
            snapshot: RecordingIndicatorProcessingSnapshot(
                step: .postProcessing,
                progressPercent: Constants.aiProcessingProgress
            )
        )
        return await runPostProcessing(
            postProcessingInput: postProcessingInput,
            prompt: prompt,
            request: request,
            qualityProfile: qualityProfile
        )
    }

    func runPostProcessing(
        postProcessingInput: String,
        prompt: PostProcessingPrompt,
        request: DomainPostProcessingRequest,
        qualityProfile: TranscriptionQualityProfile?
    ) async -> PostProcessingResult {
        let (requestSystemPrompt, requestUserPrompt) = buildRequestPrompts(
            prompt: prompt,
            from: prompt.promptText,
            transcription: postProcessingInput,
            mode: request.mode,
            selectedModel: request.configuration.modelID
        )

        do {
            let startTime = Date()
            let execution = try await executePostProcessing(
                input: postProcessingInput,
                request: request,
                mode: request.mode,
                qualityProfile: qualityProfile,
                useStructuredPipeline: request.useStructuredPipeline
            )

            let duration = Date().timeIntervalSince(startTime)
            RecordingIndicatorProcessingStateStore.shared.update(
                snapshot: RecordingIndicatorProcessingSnapshot(step: .finalizingResult, progressPercent: 100)
            )
            return PostProcessingResult(
                processedContent: execution.processedContent,
                canonicalSummary: execution.canonicalSummary,
                promptId: prompt.id,
                promptTitle: prompt.title,
                duration: duration,
                model: request.configuration.modelID,
                requestSystemPrompt: requestSystemPrompt,
                requestUserPrompt: requestUserPrompt,
                outputState: execution.outputState
            )
        } catch {
            AppLogger.error("Post-processing failed, using raw transcription", category: .recordingManager, error: error)
            RecordingIndicatorProcessingStateStore.shared.update(
                snapshot: RecordingIndicatorProcessingSnapshot(step: .postProcessingFailed, progressPercent: nil)
            )
            return PostProcessingResult(failureReason: error.localizedDescription)
        }
    }

    private func executePostProcessing(
        input: String,
        request: DomainPostProcessingRequest,
        mode: IntelligenceKernelMode,
        qualityProfile: TranscriptionQualityProfile?,
        useStructuredPipeline: Bool
    ) async throws -> PostProcessingExecution {
        let pipeline = useStructuredPipeline ? "structured" : "fast"
        let promptTitle = request.prompt?.title ?? "unknown"
        if useStructuredPipeline {
            let result = try await postProcessingRepository.processTranscriptionStructured(input, request: request)
            AppLogger.info(
                "Post-processing complete",
                category: .recordingManager,
                extra: [
                    "mode": mode.rawValue,
                    "pipeline": pipeline,
                    "prompt": promptTitle,
                    "output_state": result.outputState.rawValue
                ]
            )
            return PostProcessingExecution(
                processedContent: result.processedText,
                canonicalSummary: qualityProfile.map { recalibrateCanonicalSummary(result.canonicalSummary, with: $0) } ?? result.canonicalSummary,
                outputState: result.outputState
            )
        }

        let content = try await postProcessingRepository.processTranscription(input, request: request)
        AppLogger.info(
            "Post-processing complete",
            category: .recordingManager,
            extra: [
                "mode": mode.rawValue,
                "pipeline": pipeline,
                "prompt": promptTitle
            ]
        )
        return PostProcessingExecution(processedContent: content, canonicalSummary: nil, outputState: nil)
    }

    func resolvePostProcessingPrompt(
        rawText: String,
        isDictation: Bool,
        meetingType: MeetingType,
        snapshot: PostProcessingPromptSnapshot,
        request: DomainPostProcessingRequest
    ) async -> PostProcessingPrompt {
        if isDictation {
            return snapshot.selectedPrompt
        }

        if meetingType == .autodetect {
            return await resolveAutodetectPrompt(rawText: rawText, snapshot: snapshot, request: request)
        }

        if meetingType != .general {
            let strategy = PromptService.shared.strategy(for: meetingType)
            let prompt = strategy.promptObject()
            AppLogger.info("Using context-aware prompt for type: \(meetingType.displayName)", category: .transcriptionEngine)
            return prompt
        }

        return snapshot.selectedPrompt
    }

    func makePostProcessingPromptSnapshot(
        isDictation: Bool,
        settings: AppSettingsStore
    ) -> PostProcessingPromptSnapshot {
        let selectedPrompt = if isDictation {
            settings.selectedDictationPrompt ?? .defaultPrompt
        } else {
            settings.selectedPrompt ?? PromptService.shared.strategy(for: .general).promptObject()
        }

        return PostProcessingPromptSnapshot(
            availablePrompts: isDictation ? settings.dictationAvailablePrompts : settings.meetingAvailablePrompts,
            selectedPrompt: selectedPrompt
        )
    }

    func resolveAutodetectPrompt(
        rawText: String,
        snapshot: PostProcessingPromptSnapshot,
        request: DomainPostProcessingRequest
    ) async -> PostProcessingPrompt {
        let fallback = snapshot.selectedPrompt
        let classifierPrompt = makeMeetingTypeClassifierPrompt()

        do {
            let jsonString = try await postProcessingRepository.processTranscription(
                rawText,
                request: DomainPostProcessingRequest(
                    prompt: DomainPostProcessingPrompt(
                        id: classifierPrompt.id,
                        title: classifierPrompt.title,
                        content: classifierPrompt.promptText
                    ),
                    mode: .meeting,
                    selection: request.selection,
                    configuration: request.configuration,
                    useStructuredPipeline: false,
                    systemPromptOverride: request.systemPromptOverride
                )
            )
            guard let detectedType = parseMeetingType(from: jsonString), detectedType != .general else { return fallback }
            return resolveBuiltInMeetingPrompt(for: detectedType, fallbackGeneral: fallback)
        } catch {
            AppLogger.warning("Meeting type autodetect failed; falling back to general prompt", category: .recordingManager, extra: ["error": error.localizedDescription])
            return fallback
        }
    }

    func makeMeetingTypeClassifierPrompt() -> PostProcessingPrompt {
        PostProcessingPrompt(
            title: "Classifier",
            promptText: """
            <INTERNAL_MEETING_TYPE_CLASSIFIER>
            true
            </INTERNAL_MEETING_TYPE_CLASSIFIER>

            Analyze the transcription and classify the meeting type.
            Reply ONLY with JSON in the following format:
            { "type": "VALUE" }
            Allowed values: standup, presentation, design_review, one_on_one, planning, general.
            """,
            icon: "sparkles",
            isPredefined: false
        )
    }

    func resolveBuiltInMeetingPrompt(for type: MeetingType, fallbackGeneral: PostProcessingPrompt) -> PostProcessingPrompt {
        switch type {
        case .standup:
            .standup
        case .presentation:
            .presentation
        case .designReview:
            .designReview
        case .oneOnOne:
            .oneOnOne
        case .planning:
            .planning
        case .general:
            fallbackGeneral
        case .autodetect:
            fallbackGeneral
        }
    }

    func parseMeetingType(from jsonString: String) -> MeetingType? {
        if let type = parseMeetingTypeFromJSON(jsonString) {
            return type
        }

        guard let startIndex = jsonString.firstIndex(of: "{"),
              let endIndex = jsonString.lastIndex(of: "}")
        else {
            return nil
        }

        let candidate = String(jsonString[startIndex ... endIndex])
        return parseMeetingTypeFromJSON(candidate)
    }

    func parseMeetingTypeFromJSON(_ jsonString: String) -> MeetingType? {
        guard let data = jsonString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawType = object["type"] as? String
        else {
            return nil
        }

        let trimmed = rawType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let type = MeetingType(rawValue: trimmed) else { return nil }

        let allowed: Set<MeetingType> = [.standup, .presentation, .designReview, .oneOnOne, .planning, .general]
        return allowed.contains(type) ? type : nil
    }

    private func buildRequestPrompts(
        prompt: PostProcessingPrompt,
        from promptContent: String,
        transcription: String,
        mode: IntelligenceKernelMode,
        selectedModel: String?
    ) -> (systemPrompt: String, userPrompt: String) {
        let snapshotPrompt = PostProcessingPrompt(
            id: prompt.id,
            title: prompt.title,
            promptText: promptContent,
            isActive: prompt.isActive,
            icon: prompt.icon,
            description: prompt.description,
            isPredefined: prompt.isPredefined
        )
        let requestPrompts = AIPromptTemplates.requestPrompts(
            transcription: transcription,
            prompt: snapshotPrompt,
            mode: mode,
            selectedModel: selectedModel
        )
        return (requestPrompts.systemPrompt, requestPrompts.userPrompt)
    }
}

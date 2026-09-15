// TranscribeAudioUseCase/PostProcessing - Post-processing helpers

import Foundation
import MeetingAssistantCoreCommon

// MARK: - Post-Processing Helpers

extension TranscribeAudioUseCase {
    struct PostProcessingConfiguration {
        let applyPostProcessing: Bool
        let postProcessingPrompt: DomainPostProcessingPrompt?
        let defaultPostProcessingPrompt: DomainPostProcessingPrompt?
        let autoDetectMeetingType: Bool
        let availablePrompts: [DomainPostProcessingPrompt]
        let kernelMode: IntelligenceKernelMode
        let dictationStructuredPostProcessingEnabled: Bool
        let postProcessingModelID: String?
        let selection: DomainPostProcessingSelection?
        let configuration: DomainPostProcessingConfiguration?
        let systemPromptOverride: String?
        let failureReason: String?

        init(
            applyPostProcessing: Bool,
            postProcessingPrompt: DomainPostProcessingPrompt? = nil,
            defaultPostProcessingPrompt: DomainPostProcessingPrompt? = nil,
            autoDetectMeetingType: Bool = false,
            availablePrompts: [DomainPostProcessingPrompt] = [],
            kernelMode: IntelligenceKernelMode = .meeting,
            dictationStructuredPostProcessingEnabled: Bool = false,
            postProcessingModelID: String? = nil,
            selection: DomainPostProcessingSelection? = nil,
            configuration: DomainPostProcessingConfiguration? = nil,
            systemPromptOverride: String? = nil,
            failureReason: String? = nil
        ) {
            self.applyPostProcessing = applyPostProcessing
            self.postProcessingPrompt = postProcessingPrompt
            self.defaultPostProcessingPrompt = defaultPostProcessingPrompt
            self.autoDetectMeetingType = autoDetectMeetingType
            self.availablePrompts = availablePrompts
            self.kernelMode = kernelMode
            self.dictationStructuredPostProcessingEnabled = dictationStructuredPostProcessingEnabled
            self.postProcessingModelID = postProcessingModelID
            self.selection = selection
            self.configuration = configuration
            self.systemPromptOverride = systemPromptOverride
            self.failureReason = failureReason
        }

        func shouldRunPostProcessing(postProcessingRepository: PostProcessingRepository?) -> Bool {
            applyPostProcessing && postProcessingRepository != nil
        }
    }

    struct PostProcessingResult {
        let processedContent: String?
        let canonicalSummary: CanonicalSummary?
        let promptId: UUID?
        let promptTitle: String?
        let meetingType: String?
        let requestSystemPrompt: String?
        let requestUserPrompt: String?
        let failureReason: String?
        let outputState: DomainPostProcessingOutputState?

        init(
            processedContent: String? = nil,
            canonicalSummary: CanonicalSummary? = nil,
            promptId: UUID? = nil,
            promptTitle: String? = nil,
            meetingType: String? = nil,
            requestSystemPrompt: String? = nil,
            requestUserPrompt: String? = nil,
            failureReason: String? = nil,
            outputState: DomainPostProcessingOutputState? = nil
        ) {
            self.processedContent = processedContent
            self.canonicalSummary = canonicalSummary
            self.promptId = promptId
            self.promptTitle = promptTitle
            self.meetingType = meetingType
            self.requestSystemPrompt = requestSystemPrompt
            self.requestUserPrompt = requestUserPrompt
            self.failureReason = failureReason
            self.outputState = outputState
        }
    }

    func performPostProcessing(
        postProcessingInput: String,
        postProcessingRepository: PostProcessingRepository?,
        config: PostProcessingConfiguration,
        qualityProfile: TranscriptionQualityProfile
    ) async -> PostProcessingResult {
        guard config.applyPostProcessing, let postProcessingRepository else {
            return PostProcessingResult(
                processedContent: nil,
                canonicalSummary: nil,
                promptId: nil,
                promptTitle: nil,
                meetingType: nil,
                requestSystemPrompt: nil,
                requestUserPrompt: nil,
                failureReason: config.failureReason
            )
        }

        let context = makeExecutionContext(
            postProcessingRepository: postProcessingRepository,
            config: config,
            qualityProfile: qualityProfile
        )
        let selection = PromptSelection(
            availablePrompts: config.availablePrompts,
            fallback: config.defaultPostProcessingPrompt
        )

        do {
            if let prompt = config.postProcessingPrompt {
                return try await processWithSpecificPrompt(
                    prompt: prompt,
                    input: postProcessingInput,
                    context: context,
                    meetingType: nil
                )
            }

            if config.autoDetectMeetingType, !config.availablePrompts.isEmpty {
                return try await processWithAutoDetection(
                    input: postProcessingInput,
                    selection: selection,
                    context: context
                )
            }

            if let fallback = config.defaultPostProcessingPrompt {
                return try await processWithSpecificPrompt(
                    prompt: fallback,
                    input: postProcessingInput,
                    context: context,
                    meetingType: nil
                )
            }

            return try await processWithoutPrompt(
                input: postProcessingInput,
                context: context,
                meetingType: nil
            )
        } catch {
            AppLogger.error(
                "Post-processing failed; continuing with raw transcription",
                category: .transcriptionEngine,
                error: error
            )
            return PostProcessingResult(
                processedContent: nil,
                canonicalSummary: nil,
                promptId: nil,
                promptTitle: nil,
                meetingType: nil,
                requestSystemPrompt: nil,
                requestUserPrompt: nil,
                failureReason: error.localizedDescription
            )
        }
    }

    // MARK: - Internal Helper Structs and Methods

    private struct PostProcessingExecutionContext {
        let repository: PostProcessingRepository
        let kernelMode: IntelligenceKernelMode
        let useStructuredPipeline: Bool
        let qualityProfile: TranscriptionQualityProfile
        let selectedModel: String?
        let selection: DomainPostProcessingSelection?
        let configuration: DomainPostProcessingConfiguration
        let systemPromptOverride: String?
    }

    private struct PromptSelection {
        let availablePrompts: [DomainPostProcessingPrompt]
        let fallback: DomainPostProcessingPrompt?
    }

    private func makeExecutionContext(
        postProcessingRepository: PostProcessingRepository,
        config: PostProcessingConfiguration,
        qualityProfile: TranscriptionQualityProfile
    ) -> PostProcessingExecutionContext {
        let useStructuredPipeline = shouldUseStructuredPostProcessing(
            mode: config.kernelMode,
            dictationStructuredPostProcessingEnabled: config.dictationStructuredPostProcessingEnabled
        )

        return PostProcessingExecutionContext(
            repository: postProcessingRepository,
            kernelMode: config.kernelMode,
            useStructuredPipeline: useStructuredPipeline,
            qualityProfile: qualityProfile,
            selectedModel: config.postProcessingModelID,
            selection: config.selection,
            configuration: config.configuration ?? .unconfigured,
            systemPromptOverride: config.systemPromptOverride
        )
    }

    private func shouldUseStructuredPostProcessing(
        mode: IntelligenceKernelMode,
        dictationStructuredPostProcessingEnabled: Bool
    ) -> Bool {
        switch mode {
        case .meeting: true
        case .dictation, .assistant: dictationStructuredPostProcessingEnabled
        }
    }

    private func processWithSpecificPrompt(
        prompt: DomainPostProcessingPrompt,
        input: String,
        context: PostProcessingExecutionContext,
        meetingType: String?
    ) async throws -> PostProcessingResult {
        let (systemPrompt, userPrompt) = buildRequestPrompts(
            promptID: prompt.id,
            promptTitle: prompt.title,
            from: prompt.content,
            transcription: input,
            mode: context.kernelMode,
            selectedModel: context.selectedModel
        )

        if context.useStructuredPipeline {
            let structuredResult = try await context.repository.processTranscriptionStructured(
                input,
                request: DomainPostProcessingRequest(
                    prompt: prompt,
                    mode: context.kernelMode,
                    selection: context.selection,
                    configuration: context.configuration,
                    useStructuredPipeline: true,
                    systemPromptOverride: context.systemPromptOverride
                )
            )
            return PostProcessingResult(
                processedContent: structuredResult.processedText,
                canonicalSummary: recalibrateCanonicalSummary(
                    structuredResult.canonicalSummary,
                    with: context.qualityProfile
                ),
                promptId: prompt.id,
                promptTitle: prompt.title,
                meetingType: meetingType,
                requestSystemPrompt: systemPrompt,
                requestUserPrompt: userPrompt,
                failureReason: nil,
                outputState: structuredResult.outputState
            )
        }

        let processedContent = try await context.repository.processTranscription(
            input,
            request: DomainPostProcessingRequest(
                prompt: prompt,
                mode: context.kernelMode,
                selection: context.selection,
                configuration: context.configuration,
                useStructuredPipeline: false,
                systemPromptOverride: context.systemPromptOverride
            )
        )
        return PostProcessingResult(
            processedContent: processedContent,
            canonicalSummary: nil,
            promptId: prompt.id,
            promptTitle: prompt.title,
            meetingType: meetingType,
            requestSystemPrompt: systemPrompt,
            requestUserPrompt: userPrompt,
            failureReason: nil
        )
    }

    private func processWithAutoDetection(
        input: String,
        selection: PromptSelection,
        context: PostProcessingExecutionContext
    ) async throws -> PostProcessingResult {
        let meetingType = try await classifyMeeting(text: input, context: context)
        let normalizedType = meetingType?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased()

        if let normalizedType,
           normalizedType != "general",
           let match = findPrompt(for: normalizedType, in: selection.availablePrompts)
        {
            return try await processWithSpecificPrompt(
                prompt: match,
                input: input,
                context: context,
                meetingType: meetingType
            )
        }

        if let fallback = selection.fallback {
            return try await processWithSpecificPrompt(
                prompt: fallback,
                input: input,
                context: context,
                meetingType: meetingType
            )
        }

        return try await processWithoutPrompt(
            input: input,
            context: context,
            meetingType: meetingType
        )
    }

    private func processWithoutPrompt(
        input: String,
        context: PostProcessingExecutionContext,
        meetingType: String?
    ) async throws -> PostProcessingResult {
        if context.useStructuredPipeline {
            let structuredResult = try await context.repository.processTranscriptionStructured(
                input,
                request: DomainPostProcessingRequest(
                    mode: context.kernelMode,
                    selection: context.selection,
                    configuration: context.configuration,
                    useStructuredPipeline: true,
                    systemPromptOverride: context.systemPromptOverride
                )
            )
            return PostProcessingResult(
                processedContent: structuredResult.processedText,
                canonicalSummary: recalibrateCanonicalSummary(
                    structuredResult.canonicalSummary,
                    with: context.qualityProfile
                ),
                promptId: nil,
                promptTitle: nil,
                meetingType: meetingType,
                requestSystemPrompt: nil,
                requestUserPrompt: nil,
                failureReason: nil,
                outputState: structuredResult.outputState
            )
        }

        let processedContent = try await context.repository.processTranscription(
            input,
            request: DomainPostProcessingRequest(
                mode: context.kernelMode,
                selection: context.selection,
                configuration: context.configuration,
                useStructuredPipeline: false,
                systemPromptOverride: context.systemPromptOverride
            )
        )
        return PostProcessingResult(
            processedContent: processedContent,
            canonicalSummary: nil,
            promptId: nil,
            promptTitle: nil,
            meetingType: meetingType,
            requestSystemPrompt: nil,
            requestUserPrompt: nil,
            failureReason: nil
        )
    }

    private func classifyMeeting(
        text: String,
        context: PostProcessingExecutionContext
    ) async throws -> String? {
        let classifierPrompt = DomainPostProcessingPrompt(
            id: UUID(),
            title: "Classifier",
            content: """
            <INTERNAL_MEETING_TYPE_CLASSIFIER>
            true
            </INTERNAL_MEETING_TYPE_CLASSIFIER>

            Analise a transcrição e classifique o tipo de reunião.
            Responda APENAS com o JSON no seguinte formato:
            { "type": "VALOR" }
            Valores possíveis: standup, presentation, design_review, one_on_one, planning, general.
            """,
            isDefault: false
        )

        let jsonString = try await context.repository.processTranscription(
            text,
            request: DomainPostProcessingRequest(
                prompt: classifierPrompt,
                mode: context.kernelMode,
                selection: context.selection,
                configuration: context.configuration,
                useStructuredPipeline: false,
                systemPromptOverride: context.systemPromptOverride
            )
        )
        return parseMeetingType(from: jsonString)
    }

    private func findPrompt(for type: String, in prompts: [DomainPostProcessingPrompt]) -> DomainPostProcessingPrompt? {
        let normalizedType = normalizedMatchKey(type)

        return prompts.first { prompt in
            let normalizedTitle = normalizedMatchKey(prompt.title)
            return normalizedTitle.contains(normalizedType)
        }
    }

    private func parseMeetingType(from jsonString: String) -> String? {
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

    private func parseMeetingTypeFromJSON(_ jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawType = object["type"] as? String
        else {
            return nil
        }

        let type = rawType.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased()
        let allowed = Set(["standup", "presentation", "design_review", "one_on_one", "planning", "general"])
        return allowed.contains(type) ? type : nil
    }

    private func normalizedMatchKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .lowercased()
    }

    private func recalibrateCanonicalSummary(
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

    private func buildRequestPrompts(
        promptID: UUID,
        promptTitle: String,
        from promptContent: String,
        transcription: String,
        mode: IntelligenceKernelMode,
        selectedModel: String?
    ) -> (systemPrompt: String, userPrompt: String) {
        let prompt = PostProcessingPrompt(
            id: promptID,
            title: promptTitle,
            promptText: promptContent
        )
        let requestPrompts = AIPromptTemplates.requestPrompts(
            transcription: transcription,
            prompt: prompt,
            mode: mode,
            selectedModel: selectedModel
        )
        return (requestPrompts.systemPrompt, requestPrompts.userPrompt)
    }
}

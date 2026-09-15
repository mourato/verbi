import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

@MainActor
public struct AssistantAIPhase: @unchecked Sendable {
    private let postProcessingRepository: any PostProcessingRepository
    private let settings: AppSettingsStore
    private let runScript: @Sendable (_ script: String, _ input: String, _ timeoutSeconds: UInt64) async throws -> String?

    public init(
        postProcessingService: any PostProcessingServiceProtocol,
        scriptRunner: AssistantBashScriptRunner,
        postProcessingRepository: (any PostProcessingRepository)? = nil,
        settings: AppSettingsStore = .shared
    ) {
        self.postProcessingRepository = postProcessingRepository ?? PostProcessingRepositoryAdapter(postProcessingService: postProcessingService)
        self.settings = settings
        runScript = { script, input, timeoutSeconds in
            try await scriptRunner.run(
                script: script,
                input: input,
                timeoutSeconds: timeoutSeconds
            )
        }
    }

    init(
        postProcessingService: any PostProcessingServiceProtocol,
        runScript: @escaping @Sendable (_ script: String, _ input: String, _ timeoutSeconds: UInt64) async throws -> String?,
        postProcessingRepository: (any PostProcessingRepository)? = nil,
        settings: AppSettingsStore = .shared
    ) {
        self.postProcessingRepository = postProcessingRepository ?? PostProcessingRepositoryAdapter(postProcessingService: postProcessingService)
        self.settings = settings
        self.runScript = runScript
    }

    public func processWithAI(
        sourceText: String,
        command: String,
        executionFlow: AssistantExecutionFlow,
        selectedIntegration: AssistantIntegrationConfig?
    ) async throws -> String {
        guard let beforeAICommand = try await applyScriptIfNeeded(
            stage: .beforeAI,
            input: command,
            integration: selectedIntegration
        ) else {
            throw AssistantVoiceCommandError.processingFailed
        }

        let integrationPrompt = PostProcessingPrompt(
            title: "assistant.raycast.prompt_title".localized,
            promptText: assistantPromptInstructions(
                baseInstructions: normalizedPromptInstructions(from: selectedIntegration),
                voiceCommand: beforeAICommand,
                executionFlow: executionFlow
            )
        )
        let selection = settings.enhancementsSelection(for: .assistant)
        let configuration = settings.resolvedEnhancementsAIConfiguration(for: selection)
        let readinessIssue = settings.enhancementsInferenceReadinessIssue(
            for: selection,
            apiKeyExists: nil
        )?.rawValue

        let processedCommand = try await postProcessingRepository.processTranscription(
            sourceText,
            request: DomainPostProcessingRequest(
                prompt: DomainPostProcessingPrompt(
                    id: integrationPrompt.id,
                    title: integrationPrompt.title,
                    content: integrationPrompt.promptText
                ),
                mode: .assistant,
                selection: DomainPostProcessingSelection(
                    providerID: selection.provider.rawValue,
                    modelID: selection.selectedModel,
                    registrationID: selection.registrationID
                ),
                configuration: DomainPostProcessingConfiguration(
                    providerID: configuration.provider.rawValue,
                    baseURL: configuration.baseURL,
                    modelID: configuration.selectedModel,
                    readinessIssue: readinessIssue
                ),
                useStructuredPipeline: false,
                systemPromptOverride: executionFlow == .integrationDispatch
                    ? AIPromptTemplates.assistantSystemPrompt
                    : nil
            )
        )

        logPayloadIfNeeded("Assistant post-processing payload", [
            "length": processedCommand.count,
            "preview": AssistantPayloadLogging.payloadPreview(processedCommand)
        ])

        guard let commandForDispatch = try await applyScriptIfNeeded(
            stage: .afterAI,
            input: processedCommand,
            integration: selectedIntegration
        ) else {
            throw AssistantVoiceCommandError.processingFailed
        }

        return commandForDispatch
    }

    public func assistantPromptInstructions(
        baseInstructions: String?,
        voiceCommand: String,
        executionFlow: AssistantExecutionFlow
    ) -> String {
        let normalizedVoiceCommand = voiceCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        if executionFlow == .integrationDispatch {
            let immutableInstructions = """
            You are preparing text that will be sent to another AI assistant through a deep link.
            Rewrite or clean the command while preserving the user's intent and language.
            Never answer the command.
            Return only the final command text.
            """
            guard let baseInstructions,
                  !baseInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return [
                    immutableInstructions,
                    "User command:\n\(normalizedVoiceCommand)"
                ].joined(separator: "\n\n")
            }

            return [
                immutableInstructions,
                "Additional user instructions:\n\(baseInstructions)",
                "User command:\n\(normalizedVoiceCommand)"
            ].joined(separator: "\n\n")
        }

        guard let baseInstructions,
              !baseInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return normalizedVoiceCommand
        }

        return [
            baseInstructions,
            "Comando do usuário:\n\(normalizedVoiceCommand)"
        ].joined(separator: "\n\n")
    }

    public func normalizedPromptInstructions(from integration: AssistantIntegrationConfig?) -> String? {
        let normalized = integration?.promptInstructions?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized, !normalized.isEmpty else {
            return nil
        }
        return normalized
    }

    public func applyScriptIfNeeded(
        stage: AssistantIntegrationScriptConfig.Stage,
        input: String,
        integration: AssistantIntegrationConfig?
    ) async throws -> String? {
        guard let integration,
              integration.isEnabled,
              let scriptConfig = integration.advancedScript,
              scriptConfig.stage == stage
        else {
            return input
        }

        let output = try await runScript(scriptConfig.script, input, 15)

        if AssistantPayloadLogging.shouldLogPayloadDetails {
            AppLogger.debug(
                "Assistant script stage output",
                category: .assistant,
                extra: [
                    "stage": stage.rawValue,
                    "inputLength": input.count,
                    "outputLength": output?.count ?? 0,
                    "outputPreview": AssistantPayloadLogging.payloadPreview(output ?? "")
                ]
            )
        }

        if output == nil {
            AppLogger.info(
                "Assistant script returned empty output; skipping remaining processing",
                category: .assistant,
                extra: ["stage": stage.rawValue, "integration": integration.name]
            )
        }

        return output
    }

    private func logPayloadIfNeeded(_ message: String, _ extras: [String: Any]) {
        guard AssistantPayloadLogging.shouldLogPayloadDetails else { return }
        AppLogger.debug(message, category: .assistant, extra: extras)
    }
}

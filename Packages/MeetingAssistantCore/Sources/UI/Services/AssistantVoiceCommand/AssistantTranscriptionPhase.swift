import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

public struct AssistantTranscriptionPhase: @unchecked Sendable {
    private let transcriptionClient: any TranscriptionService

    public init(transcriptionClient: TranscriptionClient) {
        self.transcriptionClient = transcriptionClient
    }

    init(transcriptionClient: any TranscriptionService) {
        self.transcriptionClient = transcriptionClient
    }

    @MainActor
    public func performTranscription(
        recordingURL: URL,
        vocabularyReplacementRules: [VocabularyReplacementRule],
        vocabularyHints: VocabularyProviderHints? = nil,
        selection: TranscriptionProviderSelection,
        inputLanguageCode: String?,
        executionFlow: AssistantExecutionFlow,
        isAssistantIntegrationsEnabled: Bool,
        assistantSelectedIntegration: AssistantIntegrationConfig?
    ) async throws -> (
        command: String,
        executionFlow: AssistantExecutionFlow,
        selectedIntegration: AssistantIntegrationConfig?
    ) {
        let configuration = DomainTranscriptionRequestConfiguration(
            providerID: selection.provider.rawValue,
            modelID: selection.selectedModel,
            inputLanguageCode: inputLanguageCode,
            vocabularyHints: vocabularyHints
        )
        let transcription = try await transcriptionClient.transcribe(
            audioURL: recordingURL,
            onProgress: nil,
            executionMode: .assistant,
            diarizationEnabledOverride: false,
            configuration: configuration
        )
        let command = normalizedAssistantTranscription(
            transcription.text,
            vocabularyReplacementRules: vocabularyReplacementRules
        )

        logPayloadIfNeeded("Assistant transcription payload", [
            "rawLength": transcription.text.count,
            "trimmedLength": command.count,
            "preview": AssistantPayloadLogging.payloadPreview(command),
            "hasVocabularyHints": vocabularyHints.map { !$0.isEmpty } ?? false
        ])

        guard !command.isEmpty else {
            throw AssistantVoiceCommandError.emptyCommand
        }

        let selectedIntegration = resolveSelectedIntegration(
            executionFlow: executionFlow,
            isAssistantIntegrationsEnabled: isAssistantIntegrationsEnabled,
            assistantSelectedIntegration: assistantSelectedIntegration
        )

        AppLogger.info(
            "Assistant command processed",
            category: .assistant,
            extra: [
                "integration": selectedIntegration?.name ?? "assistantMode",
                "executionFlow": executionFlow == .integrationDispatch ? "integrationDispatch" : "assistantMode",
                "commandLength": command.count
            ]
        )

        return (command, executionFlow, selectedIntegration)
    }

    public func normalizedAssistantTranscription(
        _ text: String,
        vocabularyReplacementRules: [VocabularyReplacementRule]
    ) -> String {
        VocabularyReplacementRule
            .apply(rules: vocabularyReplacementRules, to: text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func resolveSelectedIntegration(
        executionFlow: AssistantExecutionFlow,
        isAssistantIntegrationsEnabled: Bool,
        assistantSelectedIntegration: AssistantIntegrationConfig?
    ) -> AssistantIntegrationConfig? {
        guard executionFlow == .integrationDispatch,
              isAssistantIntegrationsEnabled,
              let integration = assistantSelectedIntegration,
              integration.isEnabled
        else {
            return nil
        }
        return integration
    }

    private func logPayloadIfNeeded(_ message: String, _ extras: [String: Any]) {
        guard AssistantPayloadLogging.shouldLogPayloadDetails else { return }
        AppLogger.debug(message, category: .assistant, extra: extras)
    }
}

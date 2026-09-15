import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure

@MainActor
public struct AssistantDispatchPhase {
    private let raycastIntegrationService: any AssistantDeepLinkDispatching
    private let textSelectionService: AssistantTextSelectionService
    private let normalizationPhase: AssistantNormalizationPhase

    public init(
        raycastIntegrationService: any AssistantDeepLinkDispatching,
        textSelectionService: AssistantTextSelectionService,
        normalizationPhase: AssistantNormalizationPhase
    ) {
        self.raycastIntegrationService = raycastIntegrationService
        self.textSelectionService = textSelectionService
        self.normalizationPhase = normalizationPhase
    }

    func captureSourceText(
        executionFlow: AssistantExecutionFlow,
        command: String
    ) async throws -> (
        sourceText: String,
        selectedTextResult: (text: String, snapshot: AssistantTextSelectionService.PasteboardSnapshot)?
    ) {
        if executionFlow == .integrationDispatch {
            logPayloadIfNeeded("Assistant integration source payload", [
                "length": command.count,
                "preview": AssistantPayloadLogging.payloadPreview(command)
            ])
            return (command, nil)
        }

        let selectedTextCapture = try await textSelectionService.captureSelectedText()
        logPayloadIfNeeded("Assistant selected text payload", [
            "length": selectedTextCapture.text.count,
            "preview": AssistantPayloadLogging.payloadPreview(selectedTextCapture.text)
        ])
        return (selectedTextCapture.text, selectedTextCapture)
    }

    func executeDispatch(
        executionFlow: AssistantExecutionFlow,
        finalCommand: String,
        command: String,
        processedCommand: String,
        selectedIntegration: AssistantIntegrationConfig?,
        selectedTextResult: (text: String, snapshot: AssistantTextSelectionService.PasteboardSnapshot)?
    ) async throws {
        logPayloadIfNeeded("Assistant dispatch payload", [
            "length": finalCommand.count,
            "preview": AssistantPayloadLogging.payloadPreview(finalCommand),
            "integrationId": selectedIntegration?.id.uuidString ?? "assistantMode"
        ])

        if executionFlow == .integrationDispatch {
            guard let selectedIntegration else {
                throw AssistantVoiceCommandError.integrationDisabled
            }

            let dispatchResult = try dispatchToRaycast(
                with: finalCommand,
                rawText: command,
                selectedIntegration: selectedIntegration
            )
            AppLogger.info(
                "Assistant integration dispatch completed",
                category: .assistant,
                extra: [
                    "integrationId": selectedIntegration.id.uuidString,
                    "integrationName": selectedIntegration.name,
                    "result": dispatchResult == .openedWithClipboardFallback ? "clipboardFallback" : "deepLink",
                    "processedLength": processedCommand.count,
                    "dispatchedLength": finalCommand.count
                ]
            )
        } else {
            guard let selectedTextResult else {
                throw AssistantVoiceCommandError.noSelectionFound
            }
            try await textSelectionService.replaceSelectedText(
                with: finalCommand,
                restoring: selectedTextResult.snapshot
            )
            AppLogger.info(
                "Assistant mode command applied to active app",
                category: .assistant,
                extra: [
                    "processedLength": processedCommand.count,
                    "appliedLength": finalCommand.count
                ]
            )
        }
    }

    private func dispatchToRaycast(
        with command: String,
        rawText: String,
        selectedIntegration: AssistantIntegrationConfig
    ) throws -> AssistantIntegrationDispatchResult {
        let resolvedDeepLink = resolveDeepLinkShortcodes(
            in: selectedIntegration.deepLink,
            finalText: command,
            rawText: rawText
        )

        if AssistantPayloadLogging.shouldLogPayloadDetails {
            AppLogger.debug(
                "Assistant dispatch target",
                category: .assistant,
                extra: [
                    "deepLink": selectedIntegration.deepLink,
                    "resolvedDeepLink": resolvedDeepLink,
                    "commandPreview": AssistantPayloadLogging.payloadPreview(command)
                ]
            )
        }

        do {
            return try raycastIntegrationService.dispatch(
                command: command,
                baseDeepLink: resolvedDeepLink
            )
        } catch AssistantIntegrationDispatchError.invalidDeepLink {
            throw AssistantVoiceCommandError.raycastDeeplinkInvalid
        } catch AssistantIntegrationDispatchError.openFailed {
            throw AssistantVoiceCommandError.raycastOpenFailed
        }
    }

    private func resolveDeepLinkShortcodes(
        in template: String,
        finalText: String,
        rawText: String
    ) -> String {
        let replacements: [(String, String)] = [
            (AssistantIntegrationDeepLinkShortcode.finalTextURLEncoded, normalizationPhase.urlEncoded(finalText)),
            (AssistantIntegrationDeepLinkShortcode.rawTextURLEncoded, normalizationPhase.urlEncoded(rawText)),
            (AssistantIntegrationDeepLinkShortcode.finalText, finalText),
            (AssistantIntegrationDeepLinkShortcode.rawText, rawText)
        ]

        return replacements.reduce(template) { partialResult, replacement in
            partialResult.replacingOccurrences(of: replacement.0, with: replacement.1)
        }
    }

    private func logPayloadIfNeeded(_ message: String, _ extras: [String: Any]) {
        guard AssistantPayloadLogging.shouldLogPayloadDetails else { return }
        AppLogger.debug(message, category: .assistant, extra: extras)
    }
}

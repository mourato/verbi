import Foundation

public struct AssistantNormalizationPhase {
    public init() {}

    public func applyNormalization(
        processedCommand: String,
        command: String,
        executionFlow: AssistantExecutionFlow,
        sourceText: String
    ) -> String {
        let processedCommandForDispatch: String = if executionFlow == .integrationDispatch {
            (try? requireNonEmptyCommand(processedCommand, fallback: nil)) ?? processedCommand
        } else {
            normalizedCommand(processedCommand, fallback: command)
        }

        let commandToDispatch = normalizedCommand(processedCommand, fallback: processedCommandForDispatch)
        return executionFlow == .integrationDispatch
            ? commandToDispatch
            : normalizedCommand(commandToDispatch, fallback: sourceText)
    }

    public func normalizedCommand(_ command: String, fallback: String) -> String {
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.isEmpty {
            return normalized
        }

        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func requireNonEmptyCommand(_ command: String, fallback: String?) throws -> String {
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.isEmpty {
            return normalized
        }

        if let fallback {
            let normalizedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedFallback.isEmpty {
                return normalizedFallback
            }
        }

        throw AssistantVoiceCommandError.processingFailed
    }

    public func urlEncoded(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain

public extension AppSettingsStore {
    var enhancementsInferenceReadinessIssue: EnhancementsInferenceReadinessIssue? {
        enhancementsInferenceReadinessIssue(for: .meeting, apiKeyExists: nil)
    }

    var isEnhancementsInferenceReady: Bool {
        enhancementsInferenceReadinessIssue == nil
    }

    func isEnhancementsInferenceReady(for mode: IntelligenceKernelMode) -> Bool {
        enhancementsInferenceReadinessIssue(for: mode, apiKeyExists: nil) == nil
    }

    func enhancementsInferenceReadinessIssue(
        apiKeyExists: ((AIProvider) -> Bool)?
    ) -> EnhancementsInferenceReadinessIssue? {
        enhancementsInferenceReadinessIssue(for: .meeting, apiKeyExists: apiKeyExists)
    }

    func enhancementsInferenceReadinessIssue(
        for mode: IntelligenceKernelMode,
        apiKeyExists: ((AIProvider) -> Bool)?,
        registrationAPIKeyExists: ((UUID) -> Bool)? = nil
    ) -> EnhancementsInferenceReadinessIssue? {
        if let issue = checkEnhancementsInferenceReadiness(
            for: mode,
            apiKeyExists: apiKeyExists,
            registrationAPIKeyExists: registrationAPIKeyExists
        ) {
            let siblingMode = siblingEnhancementsMode(for: mode)
            if let siblingIssue = checkEnhancementsInferenceReadiness(
                for: siblingMode,
                apiKeyExists: apiKeyExists,
                registrationAPIKeyExists: registrationAPIKeyExists
            ) {
                return issue
            }
        }
        return nil
    }

    func enhancementsInferenceReadinessIssue(
        for selection: EnhancementsAISelection,
        apiKeyExists: ((AIProvider) -> Bool)?,
        registrationAPIKeyExists: ((UUID) -> Bool)? = nil
    ) -> EnhancementsInferenceReadinessIssue? {
        checkEnhancementsInferenceReadiness(
            for: selection,
            apiKeyExists: apiKeyExists,
            registrationAPIKeyExists: registrationAPIKeyExists
        )
    }

    private func checkEnhancementsInferenceReadiness(
        for mode: IntelligenceKernelMode,
        apiKeyExists: ((AIProvider) -> Bool)?,
        registrationAPIKeyExists: ((UUID) -> Bool)? = nil
    ) -> EnhancementsInferenceReadinessIssue? {
        checkEnhancementsInferenceReadiness(
            for: enhancementsSelection(for: mode),
            apiKeyExists: apiKeyExists,
            registrationAPIKeyExists: registrationAPIKeyExists
        )
    }

    private func checkEnhancementsInferenceReadiness(
        for selection: EnhancementsAISelection,
        apiKeyExists: ((AIProvider) -> Bool)?,
        registrationAPIKeyExists: ((UUID) -> Bool)? = nil
    ) -> EnhancementsInferenceReadinessIssue? {
        let config = resolvedEnhancementsAIConfiguration(for: selection)
        let selectedRegistration = enhancementsRegistration(for: selection.registrationID)
        let provider = selectedRegistration?.provider ?? selection.provider
        let hasKey: Bool = if let registrationID = selectedRegistration?.id {
            if registrationAPIKeyExists?(registrationID) ?? KeychainManager.existsAPIKey(for: registrationID) {
                true
            } else {
                apiKeyExists?(provider) ?? KeychainManager.existsAPIKey(for: provider)
            }
        } else {
            apiKeyExists?(provider) ?? KeychainManager.existsAPIKey(for: provider)
        }
        let hasModel = !config.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        guard Self.isValidHTTPURLString(config.baseURL) else {
            return .invalidBaseURL
        }

        guard hasKey else {
            return .missingAPIKey
        }

        guard hasModel else {
            return .missingModel
        }

        return nil
    }

    internal func siblingEnhancementsMode(for mode: IntelligenceKernelMode) -> IntelligenceKernelMode {
        switch mode {
        case .meeting: .dictation
        case .dictation, .assistant: .meeting
        }
    }

    func enhancementsSelection(for mode: IntelligenceKernelMode) -> EnhancementsAISelection {
        switch mode {
        case .meeting:
            enhancementsAISelection
        case .dictation, .assistant:
            enhancementsDictationAISelection
        }
    }

    func normalizedEnhancementsModelID(_ model: String, for provider: AIProvider) -> String {
        Self.normalizedEnhancementsModelID(model, for: provider)
    }

    static func normalizedEnhancementsModelID(_ model: String, for provider: AIProvider) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        guard provider == .google else { return trimmed }
        return normalizedGoogleEnhancementsModelID(trimmed)
    }
}

extension AppSettingsStore {
    static func normalizedGoogleEnhancementsModelID(_ model: String) -> String {
        let withoutPrefix: String = if model.hasPrefix("models/") {
            String(model.dropFirst("models/".count))
        } else {
            model
        }

        switch withoutPrefix.lowercased() {
        case "gemini-2.0-flash-001":
            return "gemini-2.0-flash"
        default:
            return withoutPrefix
        }
    }
}

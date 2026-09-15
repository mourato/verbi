import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain

public extension AppSettingsStore {
    func enhancementsProviderDisplayName(for selection: EnhancementsAISelection) -> String {
        enhancementsRegistration(for: selection.registrationID)?.displayName ?? selection.provider.displayName
    }

    internal func defaultRegistrationDisplayName(for provider: AIProvider) -> String {
        if provider == .custom {
            return suggestedCustomEnhancementsProviderName()
        }
        return provider.displayName
    }

    func updateEnhancementsProvider(_ provider: AIProvider) {
        var selection = enhancementsAISelection
        let targetRegistrationID = enhancementsRegistration(for: provider)?.id
        guard selection.provider != provider || selection.registrationID != targetRegistrationID else { return }
        selection.provider = provider
        selection.registrationID = targetRegistrationID
        selection.selectedModel = enhancementsSelectedModel(for: provider)
        enhancementsAISelection = selection
    }

    func updateEnhancementsSelectedModel(_ model: String) {
        var selection = enhancementsAISelection
        let normalizedModel = normalizedEnhancementsModelID(model, for: selection.provider)
        selection.selectedModel = normalizedModel
        enhancementsAISelection = selection
        setEnhancementsProviderSelectedModel(normalizedModel, for: selection.provider)
        if let registrationID = selection.registrationID {
            setEnhancementsProviderSelectedModel(normalizedModel, for: registrationID)
        }
    }

    func updateEnhancementsDictationProvider(_ provider: AIProvider) {
        var selection = enhancementsDictationAISelection
        let targetRegistrationID = enhancementsRegistration(for: provider)?.id
        guard selection.provider != provider || selection.registrationID != targetRegistrationID else { return }
        selection.provider = provider
        selection.registrationID = targetRegistrationID
        selection.selectedModel = enhancementsSelectedModel(for: provider)
        enhancementsDictationAISelection = selection
    }

    func updateEnhancementsDictationSelectedModel(_ model: String) {
        var selection = enhancementsDictationAISelection
        let normalizedModel = normalizedEnhancementsModelID(model, for: selection.provider)
        selection.selectedModel = normalizedModel
        enhancementsDictationAISelection = selection
        setEnhancementsProviderSelectedModel(normalizedModel, for: selection.provider)
        if let registrationID = selection.registrationID {
            setEnhancementsProviderSelectedModel(normalizedModel, for: registrationID)
        }
    }

    func updateEnhancementsSelection(
        provider: AIProvider,
        model: String,
        for mode: IntelligenceKernelMode
    ) {
        let registrationID = enhancementsRegistration(for: provider)?.id
        updateEnhancementsSelection(
            provider: provider,
            registrationID: registrationID,
            model: model,
            for: mode
        )
    }

    func updateEnhancementsSelection(
        registrationID: UUID,
        model: String,
        for mode: IntelligenceKernelMode
    ) {
        guard let registration = enhancementsRegistration(for: registrationID) else { return }
        updateEnhancementsSelection(
            provider: registration.provider,
            registrationID: registration.id,
            model: model,
            for: mode
        )
    }

    private func updateEnhancementsSelection(
        provider: AIProvider,
        registrationID: UUID?,
        model: String,
        for mode: IntelligenceKernelMode
    ) {
        let normalizedModel = normalizedEnhancementsModelID(model, for: provider)
        switch mode {
        case .meeting:
            enhancementsAISelection = EnhancementsAISelection(
                provider: provider,
                selectedModel: normalizedModel,
                registrationID: registrationID
            )
        case .dictation, .assistant:
            enhancementsDictationAISelection = EnhancementsAISelection(
                provider: provider,
                selectedModel: normalizedModel,
                registrationID: registrationID
            )
        }
        setEnhancementsProviderSelectedModel(normalizedModel, for: provider)
        if let registrationID {
            setEnhancementsProviderSelectedModel(normalizedModel, for: registrationID)
        }
    }

    func updateEnhancementsProviderSelectedModel(_ model: String, for provider: AIProvider) {
        setEnhancementsProviderSelectedModel(normalizedEnhancementsModelID(model, for: provider), for: provider)
    }

    func updateEnhancementsProviderSelectedModel(_ model: String, for registrationID: UUID) {
        guard let registration = enhancementsRegistration(for: registrationID) else { return }
        let normalizedModel = normalizedEnhancementsModelID(model, for: registration.provider)
        setEnhancementsProviderSelectedModel(normalizedModel, for: registration.provider)
        setEnhancementsProviderSelectedModel(normalizedModel, for: registrationID)
    }

    func enhancementsSelectedModel(for provider: AIProvider) -> String {
        if let registrationID = enhancementsRegistration(for: provider)?.id {
            let modelByRegistration = enhancementsProviderSelectedModelsByRegistration[registrationID.uuidString] ?? ""
            if !modelByRegistration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return normalizedEnhancementsModelID(modelByRegistration, for: provider)
            }
        }

        let model = enhancementsProviderSelectedModels[provider.rawValue] ?? ""
        return normalizedEnhancementsModelID(model, for: provider)
    }

    func enhancementsSelectedModel(for registrationID: UUID) -> String {
        guard let registration = enhancementsRegistration(for: registrationID) else { return "" }
        let model = enhancementsProviderSelectedModelsByRegistration[registrationID.uuidString] ?? ""
        let normalizedModel = normalizedEnhancementsModelID(model, for: registration.provider)
        if !normalizedModel.isEmpty {
            return normalizedModel
        }
        return enhancementsSelectedModel(for: registration.provider)
    }

    func isEnhancementsRegistrationSelected(
        _ registration: EnhancementsProviderRegistration,
        for mode: IntelligenceKernelMode
    ) -> Bool {
        let selection = enhancementsSelection(for: mode)
        if let selectedRegistrationID = selection.registrationID {
            return selectedRegistrationID == registration.id
        }

        guard selection.provider == registration.provider else { return false }
        return enhancementsRegistration(for: registration.provider)?.id == registration.id
    }

    /// Resolves the runtime configuration for Enhancements (post-processing + Q&A).
    var resolvedEnhancementsAIConfiguration: AIConfiguration {
        resolvedEnhancementsAIConfiguration(for: .meeting)
    }

    func resolvedEnhancementsAIConfiguration(for mode: IntelligenceKernelMode) -> AIConfiguration {
        let config = resolveEnhancementsAIConfigurationInternal(for: mode)
        let hasModel = !config.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasModel, let baseURL = URL(string: config.baseURL), baseURL.scheme != nil {
            return config
        }
        let siblingMode = siblingEnhancementsMode(for: mode)
        let siblingConfig = resolveEnhancementsAIConfigurationInternal(for: siblingMode)
        let siblingHasModel = !siblingConfig.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard siblingHasModel else { return config }
        return siblingConfig
    }

    func resolvedEnhancementsAIConfiguration(for selection: EnhancementsAISelection) -> AIConfiguration {
        resolveEnhancementsAIConfigurationInternal(for: selection)
    }

    private func resolveEnhancementsAIConfigurationInternal(for mode: IntelligenceKernelMode) -> AIConfiguration {
        resolveEnhancementsAIConfigurationInternal(for: enhancementsSelection(for: mode))
    }

    private func resolveEnhancementsAIConfigurationInternal(for selection: EnhancementsAISelection) -> AIConfiguration {
        let registration = enhancementsRegistration(for: selection.registrationID)
        let provider = registration?.provider ?? selection.provider
        let baseURL: String = if let registration {
            registration.resolvedBaseURL
        } else if provider == .custom {
            aiConfiguration.baseURL
        } else {
            provider.defaultBaseURL
        }

        let selectionModel = selection.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedModel: String = if !selectionModel.isEmpty {
            normalizedEnhancementsModelID(selectionModel, for: provider)
        } else if let registrationID = selection.registrationID {
            enhancementsSelectedModel(for: registrationID)
        } else {
            enhancementsSelectedModel(for: provider)
        }

        return AIConfiguration(
            provider: provider,
            baseURL: baseURL,
            selectedModel: selectedModel
        )
    }
}

import Foundation

public extension AppSettingsStore {
    func updateTranscriptionDictationProvider(_ provider: TranscriptionProvider) {
        let selectedModel = transcriptionSelectedModel(for: provider)
        let selection = TranscriptionProviderSelection(
            provider: provider,
            selectedModel: selectedModel
        )
        transcriptionDictationSelection = selection
        setTranscriptionProviderSelectedModel(selectedModel, for: provider)
        syncDefaultDictationStyleSelection(selection)
    }

    func updateTranscriptionDictationModel(_ model: String) {
        let provider = transcriptionDictationSelection.provider
        let normalizedModel = normalizedTranscriptionModelID(model, for: provider)
        let selection = TranscriptionProviderSelection(
            provider: provider,
            selectedModel: normalizedModel
        )
        transcriptionDictationSelection = selection
        setTranscriptionProviderSelectedModel(normalizedModel, for: provider)
        syncDefaultDictationStyleSelection(selection)
    }

    func updateTranscriptionModel(_ model: String, for provider: TranscriptionProvider) {
        let normalizedModel = normalizedTranscriptionModelID(model, for: provider)

        if transcriptionDictationSelection.provider == provider {
            let selection = TranscriptionProviderSelection(
                provider: provider,
                selectedModel: normalizedModel
            )
            transcriptionDictationSelection = selection
            syncDefaultDictationStyleSelection(selection)
        }

        setTranscriptionProviderSelectedModel(normalizedModel, for: provider)
    }

    func updateTranscriptionDictationSelection(
        provider: TranscriptionProvider,
        model: String
    ) {
        let normalizedModel = normalizedTranscriptionModelID(model, for: provider)
        let selection = TranscriptionProviderSelection(
            provider: provider,
            selectedModel: normalizedModel
        )
        transcriptionDictationSelection = selection
        setTranscriptionProviderSelectedModel(normalizedModel, for: provider)
        syncDefaultDictationStyleSelection(selection)
    }

    private func syncDefaultDictationStyleSelection(_ selection: TranscriptionProviderSelection) {
        guard let index = dictationStyles.firstIndex(where: \.isDefault) else { return }
        guard dictationStyles[index].transcriptionConfiguration.selection != selection else { return }
        var updatedStyles = dictationStyles
        updatedStyles[index].transcriptionConfiguration.selection = selection
        dictationStyles = updatedStyles
    }

    func transcriptionSelectedModel(for provider: TranscriptionProvider) -> String {
        let cachedModel = transcriptionProviderSelectedModels[provider.rawValue] ?? ""
        if !cachedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return normalizedTranscriptionModelID(cachedModel, for: provider)
        }

        if transcriptionDictationSelection.provider == provider {
            return normalizedTranscriptionModelID(transcriptionDictationSelection.selectedModel, for: provider)
        }

        return provider.defaultModelID
    }

    func normalizedTranscriptionModelID(_ model: String, for provider: TranscriptionProvider) -> String {
        provider.normalizedModelID(model)
    }

    func resolvedTranscriptionSelection(for mode: TranscriptionExecutionMode) -> TranscriptionProviderSelection {
        switch mode {
        case .meeting:
            return TranscriptionProviderSelection(
                provider: .local,
                selectedModel: meetingTranscriptionLocalModel.rawValue
            )
        case .dictation, .assistant:
            let provider = transcriptionDictationSelection.provider
            return TranscriptionProviderSelection(
                provider: provider,
                selectedModel: transcriptionSelectedModel(for: provider)
            )
        }
    }

    func updateMeetingTranscriptionLocalModel(_ model: LocalTranscriptionModel) {
        meetingTranscriptionLocalModel = model
    }

    func shouldUseRemoteTranscription(for mode: TranscriptionExecutionMode) -> Bool {
        resolvedTranscriptionSelection(for: mode).provider.usesRemoteInference
    }

    func resolvedTranscriptionInputLanguageCode(for mode: TranscriptionExecutionMode) -> String? {
        let provider = resolvedTranscriptionSelection(for: mode).provider
        switch provider {
        case .local, .groq, .elevenLabs, .openai:
            return transcriptionInputLanguageHint.languageCode
        }
    }

    func supportsIncrementalTranscription(for mode: TranscriptionExecutionMode) -> Bool {
        let selection = resolvedTranscriptionSelection(for: mode)
        guard selection.provider == .local else { return false }
        guard let localModel = LocalTranscriptionModel(rawValue: selection.selectedModel) else {
            return LocalTranscriptionModel.parakeetTdt06BV3.supportsIncrementalTranscription
        }
        return localModel.supportsIncrementalTranscription
    }

    func localModelSupportsDiarization(modelID: String) -> Bool {
        guard let model = LocalTranscriptionModel(rawValue: modelID) else { return true }
        return model.supportsDiarization
    }

    func setTranscriptionProviderSelectedModel(_ model: String, for provider: TranscriptionProvider) {
        let normalizedModel = normalizedTranscriptionModelID(model, for: provider)
        var updated = transcriptionProviderSelectedModels
        updated[provider.rawValue] = normalizedModel
        transcriptionProviderSelectedModels = updated
    }
}

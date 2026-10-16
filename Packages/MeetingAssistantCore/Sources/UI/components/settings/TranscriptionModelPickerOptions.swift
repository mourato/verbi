import MeetingAssistantCoreInfrastructure

extension ModelPickerOption where Value == TranscriptionProviderSelection {
    /// Every curated transcription model, grouped by provider, with `selection` marked selected.
    static func transcriptionOptions(
        selection: TranscriptionProviderSelection,
        status: (TranscriptionProvider, String) -> ModelPickerOptionStatus? = { _, _ in nil }
    ) -> [Self] {
        let selectedModelID = selection.provider.normalizedModelID(selection.selectedModel)
        return TranscriptionProvider.allCases.flatMap { provider in
            provider.pickerModelIDs.map { modelID in
                let identity = ModelBrand.identity(for: provider, modelID: modelID)
                return ModelPickerOption(
                    id: "\(provider.rawValue):\(modelID)",
                    value: TranscriptionProviderSelection(provider: provider, selectedModel: modelID),
                    title: provider.displayName(forModelID: modelID),
                    groupTitle: provider.displayName,
                    status: status(provider, modelID),
                    brand: identity.brand,
                    host: identity.host,
                    fallbackSymbolName: provider.iconSystemName,
                    isSelected: provider == selection.provider && modelID == selectedModelID
                )
            }
        }
    }
}

private extension TranscriptionProvider {
    var pickerModelIDs: [String] {
        switch self {
        case .local: Self.localPresetModelIDs
        case .groq: Self.groqPresetModelIDs
        case .elevenLabs: Self.elevenLabsPresetModelIDs
        case .openai: Self.openAIPresetModelIDs
        }
    }
}

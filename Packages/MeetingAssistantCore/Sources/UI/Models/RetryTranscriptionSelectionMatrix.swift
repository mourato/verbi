import MeetingAssistantCoreAI
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

@MainActor
enum RetryTranscriptionSelectionMatrix {
    static func eligibleSelections(
        for capturePurpose: CapturePurpose,
        transcriptionAPIKeyExists: (TranscriptionProvider) -> Bool,
        isLocalModelReady: (LocalTranscriptionModel) -> Bool
    ) -> [TranscriptionProviderSelection] {
        let localSelections = LocalTranscriptionModel.allCases
            .filter(isLocalModelReady)
            .map {
                TranscriptionProviderSelection(provider: .local, selectedModel: $0.rawValue)
            }

        guard capturePurpose == .dictation else {
            return localSelections
        }

        var selections = localSelections

        for provider in [TranscriptionProvider.groq, .elevenLabs] where transcriptionAPIKeyExists(provider) {
            selections.append(
                contentsOf: supportedRemoteModelIDs(for: provider).map {
                    TranscriptionProviderSelection(provider: provider, selectedModel: $0)
                }
            )
        }

        return selections
    }

    static func effectiveSelection(
        requestedOverride: TranscriptionProviderSelection?,
        capturePurpose: CapturePurpose,
        configuredSelection: TranscriptionProviderSelection,
        transcriptionAPIKeyExists: (TranscriptionProvider) -> Bool,
        isLocalModelReady: (LocalTranscriptionModel) -> Bool
    ) -> TranscriptionProviderSelection {
        guard let requestedOverride else {
            return configuredSelection
        }

        let normalizedOverride = normalizedSelection(requestedOverride)
        let eligibleSelections = eligibleSelections(
            for: capturePurpose,
            transcriptionAPIKeyExists: transcriptionAPIKeyExists,
            isLocalModelReady: isLocalModelReady
        )

        if eligibleSelections.contains(normalizedOverride) {
            return normalizedOverride
        }

        return configuredSelection
    }

    static func selectionOverrideIfNeeded(
        requestedOverride: TranscriptionProviderSelection?,
        capturePurpose: CapturePurpose,
        configuredSelection: TranscriptionProviderSelection,
        transcriptionAPIKeyExists: (TranscriptionProvider) -> Bool,
        isLocalModelReady: (LocalTranscriptionModel) -> Bool
    ) -> TranscriptionProviderSelection? {
        let effectiveSelection = effectiveSelection(
            requestedOverride: requestedOverride,
            capturePurpose: capturePurpose,
            configuredSelection: configuredSelection,
            transcriptionAPIKeyExists: transcriptionAPIKeyExists,
            isLocalModelReady: isLocalModelReady
        )

        return effectiveSelection == configuredSelection ? nil : effectiveSelection
    }

    private static func normalizedSelection(_ selection: TranscriptionProviderSelection) -> TranscriptionProviderSelection {
        TranscriptionProviderSelection(
            provider: selection.provider,
            selectedModel: selection.provider.normalizedModelID(selection.selectedModel)
        )
    }

    private static func supportedRemoteModelIDs(for provider: TranscriptionProvider) -> [String] {
        switch provider {
        case .local:
            []
        case .groq:
            TranscriptionProvider.groqPresetModelIDs
        case .elevenLabs:
            TranscriptionProvider.elevenLabsPresetModelIDs
        }
    }
}

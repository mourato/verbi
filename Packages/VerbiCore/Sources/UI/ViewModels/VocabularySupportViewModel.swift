import Combine
import Foundation
import VerbiCoreDomain
import VerbiCoreInfrastructure

/// Derives the truthful vocabulary-support summary for the dictionary settings
/// surface from the configuration owners: the resolved transcription selection,
/// the saved terms, and the AI enhancement switch.
@MainActor
public final class VocabularySupportViewModel: ObservableObject {
    private let settings: AppSettingsStore
    private var cancellables = Set<AnyCancellable>()

    public init(settings: AppSettingsStore = .shared) {
        self.settings = settings

        settings.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    /// Recognition selection used for dictation and assistant captures;
    /// snapping the summary to this owner keeps it in sync with the model picker.
    private var selection: TranscriptionProviderSelection {
        settings.resolvedTranscriptionSelection(for: .dictation)
    }

    public var providerLabel: String {
        selection.provider.displayName
    }

    public var modelLabel: String {
        selection.provider.displayName(forModelID: selection.selectedModel)
    }

    public var usesRemoteRecognition: Bool {
        selection.provider.usesRemoteInference
    }

    /// Remote AI post-processing switch; per-style dictation overrides still apply.
    public var isAIEnhancementOn: Bool {
        settings.postProcessingEnabled
    }

    public var support: VocabularyRecognitionSupport {
        VocabularyRecognitionSupport(
            parameter: selection.provider.vocabularyHelper,
            modelID: selection.selectedModel,
            snapshot: VocabularySnapshot(terms: settings.vocabularyTerms, replacementRules: [])
        )
    }
}

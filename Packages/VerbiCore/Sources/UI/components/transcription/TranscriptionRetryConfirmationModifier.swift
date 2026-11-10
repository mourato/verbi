import SwiftUI
import VerbiCoreCommon

/// Native confirmation shared by every retry entry point. The dialog explains
/// the two vocabulary intents and keeps the model override independent from
/// that choice.
struct TranscriptionRetryConfirmationModifier: ViewModifier {
    @ObservedObject var viewModel: TranscriptionLibraryViewModel

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "transcription.retry.confirm_title".localized,
                isPresented: $viewModel.showRetryConfirmation,
                titleVisibility: .visible
            ) {
                if viewModel.pendingRetryTranscription?.hasOriginalVocabulary == true {
                    Button("transcription.retry.original_settings".localized) {
                        Task {
                            await viewModel.confirmRetryTranscription(vocabularyIntent: .originalSnapshot)
                        }
                    }
                }
                Button("transcription.retry.current_dictionary".localized) {
                    Task {
                        await viewModel.confirmRetryTranscription(vocabularyIntent: .currentDictionary)
                    }
                }
                Button("common.cancel".localized, role: .cancel) {
                    viewModel.cancelRetryTranscription()
                }
            } message: {
                Text(confirmationMessage)
            }
    }

    private var confirmationMessage: String {
        guard let pending = viewModel.pendingRetryTranscription else { return "" }

        let baseMessage = if pending.hasOriginalVocabulary {
            "transcription.retry.confirm_message_original".localized
        } else {
            "transcription.retry.confirm_message_legacy".localized
        }

        if let selection = pending.selectionOverride {
            let modelName = RetryTranscriptionOption(selection: selection).displayName
            return "transcription.retry.confirm_model".localized(with: modelName) + "\n\n" + baseMessage
        }

        let providerMessage = if pending.hasOriginalVocabulary {
            "transcription.retry.confirm_provider_preserved".localized
        } else {
            "transcription.retry.confirm_provider_configured".localized
        }
        return baseMessage + "\n\n" + providerMessage
    }
}

extension View {
    func transcriptionRetryConfirmation(viewModel: TranscriptionLibraryViewModel) -> some View {
        modifier(TranscriptionRetryConfirmationModifier(viewModel: viewModel))
    }
}

import AppKit
import VerbiCoreDomain

/// History-card actions kept beside the page so the list body stays readable.
extension TranscriptionsSettingsPage {
    func openConversation(for metadata: TranscriptionMetadata) {
        guard viewModel.canOpenMeetingConversation(for: metadata) else { return }
        navigationHistory.push(.conversation(metadata.id))
        viewModel.selectedId = metadata.id
        dictationService.clearError()
    }

    func handleTranscriptionAction(
        _ action: TranscriptionCardView.TranscriptionAction,
        for metadata: TranscriptionMetadata
    ) {
        switch action {
        case .askAboutMeeting:
            openConversation(for: metadata)
        case let .copy(text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .teachCorrection:
            VocabularyQuickTeachController.shared.show()
        case let .updateMeetingTitle(title):
            Task {
                await viewModel.updateMeetingTitle(for: metadata, to: title)
            }
        case let .updateCapturePurpose(capturePurpose):
            Task {
                await viewModel.updateCapturePurpose(for: metadata, to: capturePurpose)
            }
        case .info, .viewPrompt:
            break
        case .reprocess, .requestRetryTranscription, .export:
            handleTranscriptionWorkAction(action, for: metadata)
        case .delete:
            viewModel.confirmDeleteTranscription(metadata)
        }
    }

    private func handleTranscriptionWorkAction(
        _ action: TranscriptionCardView.TranscriptionAction,
        for metadata: TranscriptionMetadata
    ) {
        switch action {
        case let .reprocess(prompt):
            Task {
                await viewModel.applyPostProcessing(prompt: prompt, transcriptionID: metadata.id)
            }
        case let .requestRetryTranscription(selection):
            Task {
                await viewModel.requestRetryTranscription(for: metadata, selectionOverride: selection)
            }
        case let .export(kind):
            let exportKind: TranscriptionLibraryViewModel.ManualTranscriptionExportKind = switch kind {
            case .summary:
                .summary
            case .original:
                .original
            }
            Task {
                await viewModel.exportTranscription(for: metadata, kind: exportKind)
            }
        case .askAboutMeeting,
             .copy,
             .teachCorrection,
             .updateMeetingTitle,
             .updateCapturePurpose,
             .info,
             .viewPrompt,
             .delete:
            break
        }
    }
}

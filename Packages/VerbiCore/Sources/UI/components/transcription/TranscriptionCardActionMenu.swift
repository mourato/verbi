import SwiftUI
import VerbiCoreAI
import VerbiCoreAudio
import VerbiCoreCommon
import VerbiCoreData
import VerbiCoreDomain
import VerbiCoreInfrastructure

/// Secondary history actions shared by the row context menu and overflow menu.
struct TranscriptionCardActionMenu: View {
    let supportsMeetingConversation: Bool
    let hasPromptText: Bool
    let hasPostProcessingContent: Bool
    let availablePrompts: [PostProcessingPrompt]
    let availableRetryTranscriptionOptions: [RetryTranscriptionOption]
    let isPostProcessing: Bool
    let audioURL: URL?
    let currentText: String
    let capturePurposeActionLabel: String
    let capturePurposeActionIcon: String
    let onAction: (TranscriptionCardView.TranscriptionAction) -> Void
    let onInfo: () -> Void
    let onViewPrompt: () -> Void
    let onToggleCapturePurpose: () -> Void

    var body: some View {
        menuContent
    }

    @ViewBuilder
    private var menuContent: some View {
        if supportsMeetingConversation {
            Button {
                onAction(.askAboutMeeting)
            } label: {
                Label("transcription.qa.title".localized, systemImage: "bubble.left.and.bubble.right")
            }
        }

        Button(action: onInfo) {
            Label("transcription.info.title".localized, systemImage: "info.circle")
        }

        if hasPromptText {
            Button(action: onViewPrompt) {
                Label("transcription.prompt.view".localized, systemImage: "text.quote")
            }
        }

        Divider()

        Button {
            onAction(.copy(text: currentText))
        } label: {
            Label("common.copy".localized, systemImage: "doc.on.doc")
        }

        Menu {
            Button {
                onAction(.export(.summary))
            } label: {
                Label("transcription.actions.export_summary".localized, systemImage: "sparkles")
            }
            .disabled(!hasPostProcessingContent)

            Button {
                onAction(.export(.original))
            } label: {
                Label("transcription.actions.export_original".localized, systemImage: "doc.plaintext")
            }
        } label: {
            Label("transcription.actions.export".localized, systemImage: "square.and.arrow.up")
        }

        Menu {
            ForEach(availablePrompts) { prompt in
                Button(prompt.title) {
                    onAction(.reprocess(prompt: prompt))
                }
            }
        } label: {
            Label("transcription.actions.redo_post_processing".localized, systemImage: "wand.and.sparkles")
        }
        .disabled(availablePrompts.isEmpty || isPostProcessing)

        if availableRetryTranscriptionOptions.count > 1 {
            Menu {
                ForEach(availableRetryTranscriptionOptions) { option in
                    Button {
                        onAction(.retryTranscription(selection: option.selection))
                    } label: {
                        retryOptionLabel(for: option)
                    }
                }
            } label: {
                Label("transcription.actions.retry_transcription".localized, systemImage: "arrow.clockwise.circle")
            }
            .disabled(audioURL == nil)
        } else {
            Button {
                if let onlyOption = availableRetryTranscriptionOptions.first {
                    onAction(.retryTranscription(selection: onlyOption.selection))
                }
            } label: {
                Label("transcription.actions.retry_transcription".localized, systemImage: "arrow.clockwise.circle")
            }
            .disabled(audioURL == nil || availableRetryTranscriptionOptions.isEmpty)
        }

        Button(action: onToggleCapturePurpose) {
            Label(capturePurposeActionLabel, systemImage: capturePurposeActionIcon)
        }

        Divider()

        Button(role: .destructive) {
            onAction(.delete)
        } label: {
            Label {
                Text("common.delete".localized)
            } icon: {
                Image(systemName: "trash")
            }
            .foregroundStyle(AppDesignSystem.Colors.error)
        }
        .foregroundStyle(AppDesignSystem.Colors.error)
    }

    /// 16pt non-template brand tile when the menu can render it in color; text only otherwise.
    @ViewBuilder
    private func retryOptionLabel(for option: RetryTranscriptionOption) -> some View {
        if let tile = BrandAvatar.menuTileImage(brand: option.brand, fallbackSymbolName: "waveform") {
            Label {
                Text(option.displayName)
            } icon: {
                Image(nsImage: tile)
            }
        } else {
            Text(option.displayName)
        }
    }
}

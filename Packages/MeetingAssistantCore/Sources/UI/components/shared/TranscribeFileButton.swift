import AppKit
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

/// Button component that opens a file picker for importing audio files to transcribe.
public struct TranscribeFileButton: View {
    @ObservedObject private var viewModel: RecordingViewModel
    @State private var pendingImportURL: URL?
    @State private var isShowingImportPurposeDialog = false

    public init(viewModel: RecordingViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Button(action: selectAndTranscribeFile) {
            Label("transcribe.import_audio".localized, systemImage: "doc.badge.arrow.up")
        }
        .buttonStyle(.bordered)
        .disabled(viewModel.isTranscribing)
        .confirmationDialog(
            "transcribe.import_audio.purpose.title".localized,
            isPresented: $isShowingImportPurposeDialog,
            titleVisibility: .visible
        ) {
            Button("transcribe.import_audio.purpose.meeting".localized) {
                transcribePendingFile(as: .meeting)
            }
            Button("transcribe.import_audio.purpose.dictation".localized) {
                transcribePendingFile(as: .dictation)
            }
            Button("common.cancel".localized, role: .cancel) {
                pendingImportURL = nil
            }
        }
    }

    private func selectAndTranscribeFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .audio,
            .mpeg4Audio,
            .mp3,
            .wav
        ]
        panel.message = "transcribe.import_audio.panel.message".localized
        panel.prompt = "transcribe.import_audio.panel.prompt".localized

        if panel.runModal() == .OK, let url = panel.url {
            pendingImportURL = url
            isShowingImportPurposeDialog = true
        }
    }

    private func transcribePendingFile(as capturePurpose: CapturePurpose) {
        guard let pendingImportURL else { return }
        self.pendingImportURL = nil

        Task {
            await viewModel.transcribeFile(at: pendingImportURL, capturePurpose: capturePurpose)
        }
    }
}

#Preview {
    TranscribeFileButton(viewModel: RecordingViewModel(recordingManager: RecordingManager.shared))
}

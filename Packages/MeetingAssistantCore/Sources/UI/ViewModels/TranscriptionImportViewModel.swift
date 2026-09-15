import AppKit
import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public class TranscriptionImportViewModel: ObservableObject {
    @Published public var isDropTargeted = false

    private let recordingManager: RecordingManager
    private let onImportSuccess: () async -> Void

    public init(
        recordingManager: RecordingManager = .shared,
        onImportSuccess: @escaping () async -> Void
    ) {
        self.recordingManager = recordingManager
        self.onImportSuccess = onImportSuccess
    }

    public func selectAndImportFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .audio, .mpeg4Audio, .mp3, .wav,
            .movie, .mpeg4Movie, .quickTimeMovie
        ]
        panel.message = "settings.transcriptions.import_select_msg".localized
        panel.prompt = "settings.transcriptions.import_prompt".localized

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await self.recordingManager.transcribeExternalAudio(from: url)
                await self.onImportSuccess()
            }
        }
    }

    public func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { @Sendable [weak self] item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil)
                else { return }

                let audioTypes = ["m4a", "mp3", "wav", "aac"]
                let videoTypes = ["mov", "mp4", "m4v"]
                let allTypes = audioTypes + videoTypes

                guard allTypes.contains(url.pathExtension.lowercased()) else { return }

                Task { @MainActor in
                    await self?.recordingManager.transcribeExternalAudio(from: url)
                    await self?.onImportSuccess()
                }
            }
        }
    }
}

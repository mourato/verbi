import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

// MARK: - External Audio Transcription

public extension RecordingManager {
    /// Transcribe an externally recorded audio file.
    /// - Parameter audioURL: Path to the audio file (m4a, mp3, wav).
    func transcribeExternalAudio(
        from audioURL: URL,
        capturePurpose: CapturePurpose = .dictation
    ) async {
        guard !isTranscribing else {
            AppLogger.info("Already transcribing", category: .recordingManager)
            return
        }

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            AppLogger.error(
                "Audio file not found for import",
                category: .recordingManager,
                extra: ["path": audioURL.path]
            )
            lastError = AudioImportError.fileNotFound
            return
        }

        let validExtensions = ["m4a", "mp3", "wav"]
        guard validExtensions.contains(audioURL.pathExtension.lowercased()) else {
            AppLogger.error(
                "Unsupported audio format for import",
                category: .recordingManager,
                extra: ["extension": audioURL.pathExtension]
            )
            lastError = AudioImportError.unsupportedFormat
            return
        }

        let meeting = Meeting(
            app: .importedFile,
            capturePurpose: capturePurpose,
            title: audioURL.deletingPathExtension().lastPathComponent,
            audioFilePath: audioURL.path
        )
        currentMeeting = meeting
        currentCapturePurpose = capturePurpose
        activePostProcessingKernelMode = capturePurpose.intelligenceKernelMode
        isMeetingMicrophoneEnabled = false
        refreshPostProcessingReadinessWarning(
            for: capturePurpose.intelligenceKernelMode
        )

        AppLogger.info(
            "Starting transcription for imported file",
            category: .recordingManager,
            extra: ["filename": audioURL.lastPathComponent]
        )
        await transcribeRecording(
            audioURL: audioURL,
            session: makeTranscriptionSessionSnapshot(meeting),
            cleanupAudioURL: nil
        )
    }
}

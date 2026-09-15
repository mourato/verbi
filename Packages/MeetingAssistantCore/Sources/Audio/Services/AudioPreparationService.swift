import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

public struct PreparedTranscriptionAudio {
    public let transcriptionURL: URL
    public let cleanupURL: URL?

    public init(transcriptionURL: URL, cleanupURL: URL?) {
        self.transcriptionURL = transcriptionURL
        self.cleanupURL = cleanupURL
    }
}

@MainActor
public final class AudioPreparationService {
    private let audioSilenceCompactor: any AudioSilenceCompacting
    private let settings: AppSettingsStore
    private let cleanupTemporaryFiles: ([URL]) -> Void

    public init(
        audioSilenceCompactor: any AudioSilenceCompacting,
        settings: AppSettingsStore,
        cleanupTemporaryFiles: @escaping ([URL]) -> Void
    ) {
        self.audioSilenceCompactor = audioSilenceCompactor
        self.settings = settings
        self.cleanupTemporaryFiles = cleanupTemporaryFiles
    }

    public func shouldRemoveSilenceBeforeTranscription(capturePurpose: CapturePurpose) -> Bool {
        let executionMode: TranscriptionExecutionMode = capturePurpose.transcriptionExecutionMode
        return !settings.shouldUseRemoteTranscription(for: executionMode)
    }

    public func prepareAudioForTranscription(
        audioURL: URL,
        allowSilenceRemoval: Bool
    ) async -> PreparedTranscriptionAudio {
        guard allowSilenceRemoval else {
            return PreparedTranscriptionAudio(transcriptionURL: audioURL, cleanupURL: nil)
        }

        guard settings.removeSilenceBeforeProcessing else {
            return PreparedTranscriptionAudio(transcriptionURL: audioURL, cleanupURL: nil)
        }

        let compactionFormat: AppSettingsStore.AudioFormat = .wav
        let tempOutputURL = temporaryCompactedAudioURL(for: compactionFormat)
        let startedAt = Date()

        do {
            let result = try await audioSilenceCompactor.compactForTranscription(
                inputURL: audioURL,
                outputURL: tempOutputURL,
                format: compactionFormat
            )
            let elapsedMs = Date().timeIntervalSince(startedAt) * 1000

            AppLogger.info(
                "Prepared compacted audio for transcription",
                category: .recordingManager,
                extra: [
                    "input": audioURL.lastPathComponent,
                    "output": result.outputURL.lastPathComponent,
                    "wasCompacted": result.wasCompacted ? "true" : "false",
                    "originalDuration": String(result.originalDuration),
                    "compactedDuration": String(result.compactedDuration),
                    "removedDuration": String(result.removedDuration),
                    "removedRatio": String(result.removedRatio),
                    "compactionDurationMs": String(elapsedMs)
                ]
            )

            PerformanceMonitor.shared.reportMetric(
                name: "audio_silence_compaction_removed_ratio",
                value: result.removedRatio,
                unit: "ratio"
            )
            PerformanceMonitor.shared.reportMetric(
                name: "audio_silence_compaction_duration_ms",
                value: elapsedMs,
                unit: "ms"
            )

            guard result.wasCompacted else {
                cleanupTemporaryFiles([tempOutputURL])
                return PreparedTranscriptionAudio(transcriptionURL: audioURL, cleanupURL: nil)
            }

            return PreparedTranscriptionAudio(
                transcriptionURL: result.outputURL,
                cleanupURL: result.outputURL
            )
        } catch {
            cleanupTemporaryFiles([tempOutputURL])
            AppLogger.warning(
                "Silence compaction failed; falling back to original audio",
                category: .recordingManager,
                extra: [
                    "input": audioURL.lastPathComponent,
                    "error": error.localizedDescription
                ]
            )
            return PreparedTranscriptionAudio(transcriptionURL: audioURL, cleanupURL: nil)
        }
    }

    public func cleanupPreparedTranscriptionAudio(_ preparedAudio: PreparedTranscriptionAudio) {
        guard let cleanupURL = preparedAudio.cleanupURL else { return }
        cleanupTemporaryFiles([cleanupURL])
    }

    private func temporaryCompactedAudioURL(for format: AppSettingsStore.AudioFormat) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("prisma-compacted-\(UUID().uuidString)")
            .appendingPathExtension(format.fileExtension)
    }
}

import Foundation
import VerbiCoreAI
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

// MARK: - Interrupted Recording Recovery

extension RecordingManager {
    /// Placeholder error recorded on the recovery entry persisted before a
    /// recovered file is retried. The retry overwrites it; it only stays
    /// visible if the app is killed again before the retry finishes.
    struct InterruptedRecordingPlaceholderError: LocalizedError {
        var errorDescription: String? {
            InterruptedRecordingRecovery.pendingFailureReason()
        }
    }

    /// Recovers audio files orphaned by a crash or forced quit.
    ///
    /// Each recoverable file is persisted as a failed recovery entry titled
    /// with the recovered-recording text, then retried through the normal
    /// library retry flow, local-first, with no prompt. Files that fail any
    /// step stay on disk and are retried on the next launch.
    /// - Returns: The number of newly recovered files.
    public func recoverInterruptedRecordings() async -> Int {
        let recordingsDir = storage.recordingsDirectory
        let scan: RecoveryScanInputs
        do {
            scan = try await collectRecoveryScanInputs(recordingsDirectory: recordingsDir)
        } catch {
            AppLogger.error(
                "Interrupted recovery scan failed",
                category: .recordingManager,
                error: error,
                extra: ["step": "load"]
            )
            return 0
        }

        var pendingFilenames = scan.pendingFilenames
        var recoveredCount = 0
        var retriedTranscriptionIDs = Set<UUID>()

        for candidate in scan.candidates {
            let filename = candidate.url.lastPathComponent
            let recovered = await recoverOrphanedFile(candidate)
            if recovered == nil {
                pendingFilenames.insert(filename)
            } else {
                pendingFilenames.remove(filename)
                recoveredCount += 1
                if let recovered {
                    retriedTranscriptionIDs.insert(recovered)
                }
            }
        }

        for metadata in scan.failedMetadata where !retriedTranscriptionIDs.contains(metadata.id) {
            await retryFailedRecoveryAttempt(metadata)
        }

        InterruptedRecordingRecovery.savePendingFilenames(pendingFilenames)
        InterruptedRecordingRecovery.saveLastScanDate(Date())

        if recoveredCount > 0 {
            AppLogger.info(
                "Interrupted recordings recovered",
                category: .recordingManager,
                extra: ["recoveredCount": "\(recoveredCount)"]
            )
            notificationService.sendInterruptedRecoveryNotification(recoveredCount: recoveredCount)
        }

        return recoveredCount
    }

    // MARK: - Scan

    private struct RecoveryScanInputs {
        let candidates: [InterruptedRecordingRecovery.Candidate]
        let failedMetadata: [TranscriptionMetadata]
        let pendingFilenames: Set<String>
    }

    private func collectRecoveryScanInputs(recordingsDirectory: URL) async throws -> RecoveryScanInputs {
        let allMetadata = try await storage.loadAllMetadata()
        let knownAudioPaths = Set(allMetadata.compactMap(\.audioFilePath))
        let activeAudioPaths = await activeRecordingAudioPaths()
        let dismissedFilenames = InterruptedRecordingRecovery.loadDismissedFilenames()
        let lastScanDate = InterruptedRecordingRecovery.loadLastScanDate()
        let pendingFilenames = InterruptedRecordingRecovery.loadPendingFilenames()

        let candidates = await Task.detached(priority: .background) {
            InterruptedRecordingRecovery.recoverableOrphans(
                in: recordingsDirectory,
                context: InterruptedRecordingRecovery.ScanContext(
                    knownAudioPaths: knownAudioPaths,
                    activeAudioPaths: activeAudioPaths,
                    dismissedFilenames: dismissedFilenames,
                    lastScanDate: lastScanDate,
                    pendingFilenames: pendingFilenames
                )
            )
        }.value

        let fileManager = FileManager.default
        let failedMetadata = allMetadata.filter { metadata in
            guard InterruptedRecordingRecovery.isFailedRecoveryMetadata(metadata) else { return false }
            guard let path = metadata.audioFilePath else { return false }
            return fileManager.fileExists(atPath: path)
        }

        return RecoveryScanInputs(
            candidates: candidates,
            failedMetadata: failedMetadata,
            pendingFilenames: pendingFilenames
        )
    }

    private func activeRecordingAudioPaths() async -> Set<String> {
        var paths = Set<String>()
        if let currentPath = currentMeeting?.audioFilePath {
            paths.insert(currentPath)
        }
        let actorURLs = await [getMicAudioURL(), getSystemAudioURL(), getMergedAudioURL()]
        for url in actorURLs.compactMap(\.self) {
            paths.insert(url.path)
        }
        return paths
    }

    // MARK: - Recover

    /// Persists one orphaned file as a failed recovery entry and retries it.
    /// - Returns: The persisted transcription ID, or nil when persistence failed.
    private func recoverOrphanedFile(_ candidate: InterruptedRecordingRecovery.Candidate) async -> UUID? {
        let meeting = CaptureSession(
            app: .manualMeeting,
            capturePurpose: .meeting,
            title: InterruptedRecordingRecovery.recoveredTitle(),
            startTime: candidate.createdAt,
            audioFilePath: candidate.url.path
        )
        let session = makeTranscriptionSessionSnapshot(meeting)
        let audioDuration = await getAudioDuration(from: candidate.url)
        let transcriptionID = UUID()
        await persistFailedTranscriptionAttempt(
            audioURL: candidate.url,
            persistedAudioURL: candidate.url,
            session: session,
            audioDuration: audioDuration,
            transcriptionIDOverride: transcriptionID,
            error: InterruptedRecordingPlaceholderError()
        )

        guard let stub = try? await storage.loadTranscription(by: transcriptionID) else {
            AppLogger.error(
                "Interrupted recovery persist failed",
                category: .recordingManager,
                extra: [
                    "filename": candidate.url.lastPathComponent,
                    "error": String(describing: type(of: InterruptedRecordingPlaceholderError()))
                ]
            )
            return nil
        }

        await retryTranscription(for: stub)
        return transcriptionID
    }

    private func retryFailedRecoveryAttempt(_ metadata: TranscriptionMetadata) async {
        guard let audioPath = metadata.audioFilePath else {
            AppLogger.error(
                "Interrupted recovery retry skipped",
                category: .recordingManager,
                extra: ["filename": "unknown"]
            )
            return
        }
        guard let transcription = try? await storage.loadTranscription(by: metadata.id) else {
            AppLogger.error(
                "Interrupted recovery retry skipped",
                category: .recordingManager,
                extra: ["filename": URL(fileURLWithPath: audioPath).lastPathComponent]
            )
            return
        }
        await retryTranscription(for: transcription)
    }
}

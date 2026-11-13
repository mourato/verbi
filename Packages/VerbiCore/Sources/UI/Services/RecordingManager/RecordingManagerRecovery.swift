import Foundation
import VerbiCoreAI
import VerbiCoreCommon
import VerbiCoreData
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
    /// library retry flow with the user's configured providers, local-first,
    /// with no prompt and a single summary notification. Files that fail any
    /// step stay on disk and are retried on the next launch, up to the
    /// attempt cap.
    /// - Returns: The number of newly recovered files (only successes count).
    public func recoverInterruptedRecordings() async -> Int {
        let recordingsDir = storage.recordingsDirectory
        let flow = InterruptedRecoveryFlow(io: recoveryFlowIO())
        return await flow.run(recordingsDirectory: recordingsDir)
    }

    // MARK: - Flow wiring

    private func recoveryFlowIO() -> InterruptedRecoveryFlow.Dependencies {
        InterruptedRecoveryFlow.Dependencies(
            loadStores: { InterruptedRecordingRecovery.loadStores() },
            saveStores: { InterruptedRecordingRecovery.saveStores($0) },
            listMetadata: { [weak self] in
                guard let self else { return [] }
                return try await storage.loadAllMetadata()
            },
            loadArtifact: { [weak self] id in
                guard let self else { return nil }
                return try? await storage.loadTranscription(by: id)
            },
            activeAudioPaths: { [weak self] in
                await self?.recoveryActiveAudioPaths() ?? []
            },
            persistStub: { [weak self] request in
                await self?.persistRecoveryStub(request)
            },
            retryArtifact: { [weak self] transcription in
                await self?.retryRecoveryArtifact(transcription) ?? false
            },
            mergeSplitParts: { [weak self] parts, output in
                await self?.mergeRecoverySplitParts(parts, output: output)
            },
            audioDuration: { [weak self] url in
                await self?.getAudioDuration(from: url)
            },
            isBusy: { [weak self] in
                await MainActor.run {
                    self?.isTranscribing == true || self?.isRecording == true || self?.isStartingRecording == true
                }
            },
            notifySummary: { [weak self] count in
                await MainActor.run {
                    self?.notificationService.sendInterruptedRecoveryNotification(recoveredCount: count)
                }
            },
            now: { Date() }
        )
    }

    /// Audio paths the recovery scan must not claim: the current meeting, the
    /// recorder outputs, and every session with an unsaved transcription.
    private func recoveryActiveAudioPaths() async -> Set<String> {
        var paths = Set<String>()
        if let currentPath = currentMeeting?.audioFilePath {
            paths.insert(currentPath)
        }
        if let micURL = await getMicAudioURL() {
            paths.insert(micURL.path)
        }
        if let systemURL = await getSystemAudioURL() {
            paths.insert(systemURL.path)
        }
        if let mergedURL = await getMergedAudioURL() {
            paths.insert(mergedURL.path)
        }
        for path in inFlightTranscriptionAudioPaths.values {
            paths.insert(path)
        }
        return paths
    }

    private func persistRecoveryStub(_ request: InterruptedRecoveryFlow.StubRequest) async -> UUID? {
        let meeting = CaptureSession(
            app: request.capturePurpose == .dictation ? .unknown : .manualMeeting,
            capturePurpose: request.capturePurpose,
            title: request.title,
            startTime: request.startTime,
            audioFilePath: request.audioURL.path
        )
        let session = makeRecoveryTranscriptionSessionSnapshot(meeting)
        let audioDuration = await getAudioDuration(from: request.audioURL)
        let transcriptionID = UUID()
        await persistFailedTranscriptionAttempt(
            audioURL: request.audioURL,
            persistedAudioURL: request.audioURL,
            session: session,
            audioDuration: audioDuration,
            transcriptionIDOverride: transcriptionID,
            error: InterruptedRecordingPlaceholderError()
        )

        let persisted = try? await storage.loadTranscription(by: transcriptionID)
        guard persisted != nil else {
            AppLogger.error(
                "Interrupted recovery persist failed",
                category: .recordingManager,
                extra: ["filename": request.audioURL.lastPathComponent, "step": "persist"]
            )
            return nil
        }
        return transcriptionID
    }

    /// Retries a recovery entry without per-file user notifications and
    /// reports whether the entry now holds a completed transcription.
    private func retryRecoveryArtifact(_ transcription: CaptureArtifact) async -> Bool {
        if isTranscribing {
            return false
        }
        await retryTranscription(for: transcription, vocabularyIntent: .originalSnapshot, recoveryMode: true)
        guard let updated = try? await storage.loadTranscription(by: transcription.id) else {
            return false
        }
        return updated.lifecycleState == .completed
    }

    private func mergeRecoverySplitParts(_ parts: [URL], output: URL) async -> URL? {
        let format: AppSettingsStore.AudioFormat = output.pathExtension.lowercased() == "m4a" ? .m4a : .wav
        do {
            return try await audioMerger.mergeAudioFiles(inputURLs: parts, to: output, format: format)
        } catch {
            AppLogger.error(
                "Interrupted recovery merge failed",
                category: .recordingManager,
                error: error,
                extra: ["filename": output.lastPathComponent]
            )
            return nil
        }
    }
}

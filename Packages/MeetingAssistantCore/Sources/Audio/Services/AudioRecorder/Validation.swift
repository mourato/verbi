@preconcurrency import AVFoundation
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain

extension AudioRecorder {
    // MARK: - Validation & Retry

    func startValidationTimer(url: URL, source: RecordingSource, retryCount: Int) {
        let sessionID = UUID()
        activeValidationSessionID = sessionID
        validationTimer = Timer.scheduledTimer(
            withTimeInterval: Constants.validationInterval, repeats: false
        ) { @Sendable [weak self] _ in
            Task { @MainActor in
                await self?.handleValidationTimeout(
                    url: url,
                    source: source,
                    retryCount: retryCount,
                    sessionID: sessionID
                )
            }
        }
    }

    func handleValidationTimeout(
        url: URL,
        source: RecordingSource,
        retryCount: Int,
        sessionID: UUID
    ) async {
        guard isCurrentValidationSession(sessionID, url: url, source: source) else { return }

        let validationPassed = await worker.getHasReceivedValidBuffer()

        guard isCurrentValidationSession(sessionID, url: url, source: source) else { return }

        guard !validationPassed else {
            AppLogger.info("Recording validation successful", category: .recordingManager)
            return
        }

        AppLogger.error("Recording validation failed - no valid buffers received", category: .recordingManager)
        _ = await stopRecording()

        guard activeValidationSessionID == sessionID else { return }

        if source == .microphone {
            do {
                try startFallbackRecorder(to: url)
                AppLogger.warning(
                    "Switched to fallback microphone recorder after validation failure",
                    category: .recordingManager,
                    extra: ["path": url.path]
                )
                return
            } catch {
                AppLogger.error(
                    "Failed to start fallback microphone recorder",
                    category: .recordingManager,
                    error: error
                )
            }
        }

        if retryCount < Constants.maxRetries {
            await retryRecording(to: url, source: source, retryCount: retryCount)
        } else {
            AppLogger.fault("Recording failed after retries", category: .recordingManager)
            let error = AudioRecorderError.recordingValidationFailed
            self.error = error
            onRecordingError?(error)
        }
    }

    private func isCurrentValidationSession(_ sessionID: UUID, url: URL, source: RecordingSource) -> Bool {
        activeValidationSessionID == sessionID
            && isRecording
            && currentRecordingURL == url
            && activeRecordingSource == source
    }

    func retryRecording(to url: URL, source: RecordingSource, retryCount: Int) async {
        AppLogger.info(
            "Retrying recording",
            category: .recordingManager,
            extra: ["attempt": retryCount + 1, "max": Constants.maxRetries]
        )
        do {
            try await Task.sleep(nanoseconds: Constants.retryDelay)
            try await startRecording(to: url, source: source, retryCount: retryCount + 1)
        } catch {
            AppLogger.error("Retry failed", category: .recordingManager, error: error)
            self.error = error
            onRecordingError?(error)
        }
    }

    func handleWorkerError(_ error: Error) {
        AppLogger.error("Worker error", category: .recordingManager, error: error)
        self.error = error
    }

    func verifyFileIntegrity(url: URL) {
        let asset = AVURLAsset(url: url)
        Task {
            do {
                let duration = try await asset.load(.duration)
                AppLogger.info(
                    "Recording saved",
                    category: .recordingManager,
                    extra: ["filename": url.lastPathComponent, "duration": duration.seconds]
                )
            } catch {
                AppLogger.error("Verification failed", category: .recordingManager, error: error)
            }
        }
    }
}

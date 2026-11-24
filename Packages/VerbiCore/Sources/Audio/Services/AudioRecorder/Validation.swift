@preconcurrency import AVFoundation
import Foundation
import VerbiCoreCommon
import VerbiCoreDomain

extension AudioRecorder {
    func startValidationTimer(url: URL, source: RecordingSource, retryCount: Int, allowsRestart: Bool = true) {
        let sessionID = UUID()
        activeValidationSessionID = sessionID
        validationTimer = Timer.scheduledTimer(
            withTimeInterval: validationInterval, repeats: false
        ) { @Sendable [weak self] _ in
            Task { @MainActor in
                await self?.handleValidationTimeout(
                    url: url,
                    source: source,
                    retryCount: retryCount,
                    sessionID: sessionID,
                    allowsRestart: allowsRestart
                )
            }
        }
    }

    func handleValidationTimeout(
        url: URL,
        source: RecordingSource,
        retryCount: Int,
        sessionID: UUID,
        allowsRestart: Bool = true
    ) async {
        guard isCurrentValidationSession(sessionID, url: url, source: source) else { return }

        let validationPassed = await worker.getHasReceivedValidBuffer()

        guard isCurrentValidationSession(sessionID, url: url, source: source) else { return }

        guard !validationPassed else {
            AppLogger.info("Recording validation successful", category: .recordingManager)
            return
        }

        AppLogger.error("Recording validation failed - no valid buffers received", category: .recordingManager)

        guard allowsRestart else {
            let error = AudioRecorderError.recordingValidationFailed
            self.error = error
            if let onRecordingError {
                onRecordingError(error)
            } else {
                _ = await stopRecording()
            }
            return
        }

        restartingCaptureURL = url
        defer {
            if restartingCaptureURL == url {
                restartingCaptureURL = nil
            }
        }

        _ = await finalizeCapture()

        guard activeValidationSessionID == sessionID else { return }

        let maxAttempts = source == .microphone ? 1 : Constants.maxRetries
        if retryCount < maxAttempts {
            await retryRecording(to: url, source: source, retryCount: retryCount)
        } else {
            AppLogger.fault("Recording failed after retries", category: .recordingManager)
            reportRecordingFailure(AudioRecorderError.recordingValidationFailed)
        }
    }

    private func isCurrentValidationSession(_ sessionID: UUID, url: URL, source: RecordingSource) -> Bool {
        activeValidationSessionID == sessionID
            && isRecording
            && currentRecordingURL == url
            && activeRecordingSource == source
    }

    private func retryRecording(to url: URL, source: RecordingSource, retryCount: Int) async {
        let generation = captureGeneration
        AppLogger.info(
            "Retrying recording",
            category: .recordingManager,
            extra: ["attempt": retryCount + 1, "max": Constants.maxRetries]
        )
        do {
            try await Task.sleep(nanoseconds: Constants.retryDelay)
            try ensureCaptureGeneration(generation)
            try await startRecording(to: url, source: source, retryCount: retryCount + 1)
        } catch {
            guard captureGeneration == generation else { return }
            AppLogger.error("Retry failed", category: .recordingManager, error: error)
            reportRecordingFailure(error)
        }
    }

    private func reportRecordingFailure(_ error: Error) {
        self.error = error
        onRecordingError?(error)
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

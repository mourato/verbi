import AVFoundation
import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

// MARK: - Transcription Progress and Notifications

extension RecordingManager {
    func handleUseCasePhaseChange(_ phase: TranscriptionPhase, meeting: Meeting, sessionID: UUID) {
        switch phase {
        case .preparing:
            updateVisibleTranscriptionProgress(phase: .preparing, sessionID: sessionID)
        case .processing:
            updateVisibleTranscriptionProgress(
                phase: .processing,
                percentage: max(Constants.processingProgress, transcriptionStatus.progressPercentage),
                sessionID: sessionID
            )
        case .postProcessing:
            let startProgress = max(Constants.postProcessingProgress, transcriptionStatus.progressPercentage)
            updateVisibleTranscriptionProgress(
                phase: .postProcessing,
                percentage: startProgress,
                sessionID: sessionID
            )
            if meeting.capturePurpose == .meeting, meeting.type == .autodetect {
                updateIndicatorProcessingSnapshot(
                    step: .detectingMeetingType,
                    progressPercent: startProgress,
                    sessionID: sessionID
                )
            }

            if meeting.capturePurpose == .meeting {
                startEstimatedPostProcessingProgress(from: startProgress, sessionID: sessionID)
            }
        case .completed:
            cancelEstimatedPostProcessingProgress(for: sessionID)
        case .failed:
            cancelEstimatedPostProcessingProgress(for: sessionID)
        case .idle:
            break
        }
    }

    func handleUseCaseTranscriptionProgress(_ progress: Double, sessionID: UUID) {
        let clamped = min(max(progress, 0), 100)
        let processingRange = Constants.postProcessingProgress - Constants.processingProgress
        let mappedProgress = Constants.processingProgress + (clamped / 100.0 * processingRange)
        updateVisibleTranscriptionProgress(
            phase: .processing,
            percentage: mappedProgress,
            sessionID: sessionID
        )
    }

    func startEstimatedPostProcessingProgress(from startProgress: Double, sessionID: UUID) {
        guard shouldDriveForegroundTranscriptionUI(for: sessionID) else { return }

        cancelEstimatedPostProcessingProgress(for: sessionID)

        let clampedStart = min(max(startProgress, Constants.postProcessingProgress), Constants.postProcessingProgressCeiling)
        estimatedPostProcessingProgressSessionID = sessionID
        updateVisibleTranscriptionProgress(
            phase: .postProcessing,
            percentage: clampedStart,
            sessionID: sessionID
        )

        estimatedPostProcessingProgressTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let startDate = Date()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Constants.postProcessingProgressTickNanoseconds)
                guard !Task.isCancelled else { return }

                let elapsed = Date().timeIntervalSince(startDate)
                let easedProgress = Constants.postProcessingProgressCeiling
                    - (Constants.postProcessingProgressCeiling - clampedStart) * exp(-elapsed / Constants.postProcessingProgressSmoothingTau)
                let nextProgress = min(Constants.postProcessingProgressCeiling, max(clampedStart, easedProgress))
                updateVisibleTranscriptionProgress(
                    phase: .postProcessing,
                    percentage: nextProgress,
                    sessionID: sessionID
                )
            }
        }
    }

    func cancelEstimatedPostProcessingProgress(for sessionID: UUID? = nil) {
        if let sessionID, estimatedPostProcessingProgressSessionID != sessionID {
            return
        }
        estimatedPostProcessingProgressTask?.cancel()
        estimatedPostProcessingProgressTask = nil
        estimatedPostProcessingProgressSessionID = nil
    }

    // MARK: - Notifications

    func notifySuccess(for transcription: Transcription) {
        let body: String
        if let failureReason = transcription.transcriptionFailureReason
            ?? transcription.postProcessingFailureReason
        {
            let usesPostProcessingFailure = transcription.transcriptionFailureReason == nil
                && transcription.postProcessingFailureReason != nil
            if usesPostProcessingFailure {
                RecordingIndicatorProcessingStateStore.shared.update(
                    snapshot: RecordingIndicatorProcessingSnapshot(
                        step: .postProcessingFailed,
                        progressPercent: nil
                    )
                )
            }
            body = "notification.transcription_body_with_post_processing_failure".localized(
                with: transcription.meeting.appName,
                transcription.wordCount,
                failureReason
            )
        } else {
            let suffix = transcription.isPostProcessed
                ? "notification.transcription_processed".localized
                : "notification.transcription_transcribed".localized
            body = "notification.transcription_body".localized(
                with: transcription.meeting.appName,
                transcription.wordCount,
                suffix
            )
        }

        notificationService.sendNotification(
            title: "notification.transcription_completed".localized,
            body: body
        )

        NotificationCenter.default.post(
            name: .meetingAssistantTranscriptionSaved,
            object: nil,
            userInfo: [AppNotifications.UserInfoKey.transcriptionId: transcription.id.uuidString]
        )
    }

    func handleTranscriptionError(_ error: Error, sessionID: UUID? = nil) {
        AppLogger.error("Transcription failed", category: .recordingManager, error: error)
        lastError = error
        cancelEstimatedPostProcessingProgress(for: sessionID)

        updateIndicatorProcessingSnapshot(
            step: .transcribingFailed,
            progressPercent: nil,
            sessionID: sessionID
        )

        let statusError = transcriptionStatusError(from: error)

        if shouldDriveForegroundTranscriptionUI(for: sessionID) {
            transcriptionStatus.recordError(statusError)
            transcriptionStatus.completeTranscription(success: false)
        }

        NotificationCenter.default.post(
            name: .meetingAssistantTranscriptionFailed,
            object: nil,
            userInfo: [AppNotifications.UserInfoKey.transcriptionErrorMessage: statusError.localizedDescription]
        )

        notificationService.sendNotification(
            title: "notification.transcription_failed".localized,
            body: statusError.localizedDescription
        )
    }

    func transcriptionStatusError(from error: Error) -> TranscriptionStatusError {
        switch error {
        case let error as TranscriptionError:
            switch error {
            case .serviceUnavailable:
                .serviceUnavailable
            case .warmupFailed:
                .modelLoadFailed(error.localizedDescription)
            case .invalidResponse:
                .transcriptionFailed(error.localizedDescription)
            case .invalidURL:
                .connectionFailed(error.localizedDescription)
            case let .transcriptionFailed(message):
                .transcriptionFailed(message)
            }
        case let error as DomainTranscriptionError:
            switch error {
            case .serviceUnavailable:
                .serviceUnavailable
            case .invalidAudioFile:
                .transcriptionFailed("error.transcription.invalid_audio_file".localized)
            case let .transcriptionFailed(message):
                .transcriptionFailed(message)
            case let .postProcessingFailed(message):
                .transcriptionFailed(message)
            }
        case let error as PostProcessingError:
            .transcriptionFailed(error.localizedDescription)
        case let error as RecordingManagerError:
            switch error {
            case .noOutputPath:
                .transcriptionFailed("error.transcription.no_output_path".localized)
            case .mergeFailed:
                .transcriptionFailed("error.transcription.merge_failed".localized)
            case .noInputFiles:
                .transcriptionFailed("error.transcription.no_input_files".localized)
            }
        default:
            .transcriptionFailed(error.localizedDescription)
        }
    }

    func scheduleStatusReset(sessionID: UUID? = nil) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Constants.statusResetDelay))
            guard self.shouldResetVisibleTranscriptionStatus(for: sessionID) else { return }
            self.transcriptionStatus.resetToIdle()
            self.resetIndicatorProcessingSnapshot(sessionID: sessionID)
        }
    }

    func registerTranscriptionSession(_ sessionID: UUID, foreground: Bool) {
        activeTranscriptionSessionIDs.insert(sessionID)
        isTranscribing = true

        guard foreground else { return }
        foregroundTranscriptionSessionID = sessionID
        isForegroundTranscribing = true
    }

    func unregisterTranscriptionSession(_ sessionID: UUID) {
        activeTranscriptionSessionIDs.remove(sessionID)
        isTranscribing = !activeTranscriptionSessionIDs.isEmpty

        if foregroundTranscriptionSessionID == sessionID {
            foregroundTranscriptionSessionID = nil
            isForegroundTranscribing = false
        }
    }

    func shouldDriveForegroundTranscriptionUI(for sessionID: UUID?) -> Bool {
        guard let sessionID else { return true }
        return foregroundTranscriptionSessionID == sessionID
    }

    func shouldResetVisibleTranscriptionStatus(for sessionID: UUID?) -> Bool {
        guard let sessionID else { return true }
        return foregroundTranscriptionSessionID == nil || foregroundTranscriptionSessionID == sessionID
    }

    func shouldDriveSharedTranscriptionState(for sessionID: UUID) -> Bool {
        if currentMeeting?.id == sessionID {
            return true
        }

        return !isRecording && !isStartingRecording
    }

    func beginVisibleTranscriptionStatus(audioDuration: Double?, sessionID: UUID?) {
        guard shouldDriveForegroundTranscriptionUI(for: sessionID) else { return }
        transcriptionStatus.beginTranscription(audioDuration: audioDuration)
        updateIndicatorProcessingSnapshot(step: .preparingAudio, progressPercent: 0, sessionID: sessionID)
    }

    func updateVisibleTranscriptionProgress(
        phase: TranscriptionPhase,
        percentage: Double? = nil,
        sessionID: UUID?
    ) {
        guard shouldDriveForegroundTranscriptionUI(for: sessionID) else { return }
        transcriptionStatus.updateProgress(phase: phase, percentage: percentage)
        if let step = indicatorProcessingStep(for: phase) {
            updateIndicatorProcessingSnapshot(step: step, progressPercent: percentage, sessionID: sessionID)
        }
    }

    func completeVisibleTranscription(success: Bool, sessionID: UUID?) {
        guard shouldDriveForegroundTranscriptionUI(for: sessionID) else { return }
        transcriptionStatus.completeTranscription(success: success)
    }

    func indicatorProcessingStep(for phase: TranscriptionPhase) -> RecordingIndicatorProcessingStep? {
        switch phase {
        case .idle:
            nil
        case .failed:
            .transcribingFailed
        case .preparing:
            .preparingAudio
        case .processing:
            .transcribingAudio
        case .postProcessing:
            .postProcessing
        case .completed:
            .finalizingResult
        }
    }

    func updateIndicatorProcessingSnapshot(
        step: RecordingIndicatorProcessingStep,
        progressPercent: Double? = nil,
        sessionID: UUID?
    ) {
        guard shouldDriveForegroundTranscriptionUI(for: sessionID) else { return }
        RecordingIndicatorProcessingStateStore.shared.update(
            snapshot: RecordingIndicatorProcessingSnapshot(
                step: step,
                progressPercent: progressPercent
            )
        )
    }

    func resetIndicatorProcessingSnapshot(sessionID: UUID?) {
        guard shouldResetVisibleTranscriptionStatus(for: sessionID) else { return }
        RecordingIndicatorProcessingStateStore.shared.reset()
    }

    /// Get audio duration from file for progress estimation.
    func getAudioDuration(from url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            return duration.seconds
        } catch {
            AppLogger.error("Failed to load audio duration", category: .recordingManager, error: error)
            return nil
        }
    }
}

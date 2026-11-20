import Foundation
import VerbiCoreAI
import VerbiCoreAudio
import VerbiCoreCommon
import VerbiCoreData
import VerbiCoreDomain
import VerbiCoreInfrastructure

// MARK: - Recording Stop and Cancellation

public extension RecordingManager {
    /// Stop recording and optionally transcribe.
    func stopRecording() async {
        await stopRecording(transcribe: true)
    }

    // swiftlint:disable:next function_body_length
    func stopRecording(transcribe: Bool = true) async {
        var transcriptionSession: TranscriptionSessionSnapshot?
        var mergedAudioURL: URL?
        var incrementalDictationCoordinator: IncrementalTranscriptionCoordinator?
        var incrementalMeetingCoordinator: IncrementalTranscriptionCoordinator?
        await lifecycleCoordinator.stop(
            isRecording: isRecording,
            transcribe: transcribe,
            operations: lifecycleOperations,
            actions: RecordingLifecycleCoordinator.StopActions(
                accepted: {
                    self.resetMeetingEndPromptState()
                },
                beforeRelease: { recordings in
                    self.isStartingRecording = false
                    self.currentMeeting?.endTime = Date()
                    transcriptionSession = self.prepareStopState(transcribe: transcribe)
                    mergedAudioURL = await self.getMergedAudioURL()
                    incrementalDictationCoordinator = self.incrementalDictationCoordinator
                    incrementalMeetingCoordinator = self.incrementalMeetingCoordinator
                    self.isRecording = false
                    AppLogger.info("Recording stopped", category: .recordingManager, extra: [
                        "micURL": recordings.mic?.lastPathComponent ?? "nil",
                        "sysURL": recordings.system?.lastPathComponent ?? "nil"
                    ])
                },
                finalize: { recordings in
                    let finalURL = try await self.processRecordedAudio(
                        micURL: recordings.mic,
                        sysURL: recordings.system,
                        mergedAudioURL: mergedAudioURL,
                        usesIncrementalDictation: incrementalDictationCoordinator != nil
                    )

                    if transcribe, let transcriptionSession {
                        if let incrementalDictationCoordinator,
                           transcriptionSession.meeting.capturePurpose == .dictation
                        {
                            await self.transcribeIncrementalSession(
                                audioURL: finalURL,
                                session: transcriptionSession,
                                coordinator: incrementalDictationCoordinator,
                                coordinatorKind: .dictation
                            )
                        } else if let incrementalMeetingCoordinator,
                                  transcriptionSession.meeting.capturePurpose == .meeting
                        {
                            await self.transcribeIncrementalSession(
                                audioURL: finalURL,
                                session: transcriptionSession,
                                coordinator: incrementalMeetingCoordinator,
                                coordinatorKind: .meeting
                            )
                        } else {
                            let preparedAudio = await self.prepareAudioForTranscription(
                                audioURL: finalURL,
                                allowSilenceRemoval: self.shouldRemoveSilenceBeforeTranscription(for: transcriptionSession)
                            )
                            await self.transcribeRecording(
                                audioURL: preparedAudio.transcriptionURL,
                                session: transcriptionSession,
                                cleanupAudioURL: preparedAudio.cleanupURL
                            )
                        }
                    }
                },
                handleFailure: { error, recordings in
                    await self.handleStopRecordingError(
                        error,
                        recordings: recordings,
                        transcriptionSession: transcriptionSession,
                        mergedAudioURL: mergedAudioURL
                    )
                }
            )
        )
    }

    /// Cancel recording and discard audio files.
    func cancelRecording() async {
        let wasRecording = isRecording
        let wasStarting = isStartingRecording
        guard wasRecording || wasStarting || isStartOperationInFlight else { return }

        resetMeetingEndPromptState()
        MeetingDetectionToastController.shared.hide()
        meetingDetectionToastStartContext = nil
        let capturePurpose = currentCapturePurpose
        AppLogger.info(
            wasRecording ? "Cancelling recording..." : "Cancelling recording during startup...",
            category: .recordingManager
        )
        await lifecycleCoordinator.cancel(
            isRecording: wasRecording,
            isStarting: wasStarting,
            operations: lifecycleOperations
        )
        AppLogger.info(
            wasRecording ? "Recording cancelled and files discarded" : "Recording startup cancelled",
            category: .recordingManager
        )
        scheduleDictationPostSessionUnloadIfNeeded(for: capturePurpose)
    }
}

private extension RecordingManager {
    func prepareStopState(transcribe: Bool) -> TranscriptionSessionSnapshot? {
        MeetingDetectionToastController.shared.hide()
        let session = currentMeeting.map(makeTranscriptionSessionSnapshot)
        clearActiveTranscriptionSnapshot()

        if transcribe, let session {
            registerTranscriptionSession(session.id, foreground: true)
            if let audioFilePath = session.meeting.audioFilePath {
                inFlightTranscriptionAudioPaths[session.id] = audioFilePath
            }
            // Delay the transient transcribing state so fast tail
            // finalizations skip a redundant main-thread pill redraw.
            scheduleDelayedTranscribingState(sessionID: session.id)
        } else {
            meetingState = .idle
            currentMeeting?.state = .completed
        }

        return session
    }

    /// Shows `.processing(.transcribing)` only when finalization outlives the
    /// delay. Fast stops unregister first, so no transient state is ever shown.
    func scheduleDelayedTranscribingState(sessionID: UUID) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .nanoseconds(Int64(RemoteIncrementalDictationPolicy.transcribingStateDelayNanoseconds)))
            guard let self,
                  activeTranscriptionSessionIDs.contains(sessionID),
                  foregroundTranscriptionSessionID == sessionID
            else { return }
            if shouldDriveSharedTranscriptionState(for: sessionID) {
                meetingState = .processing(.transcribing)
            }
            if currentMeeting?.id == sessionID {
                currentMeeting?.state = .processing(.transcribing)
            }
        }
    }

    func scheduleDictationPostSessionUnloadIfNeeded(for capturePurpose: CapturePurpose?) {
        guard capturePurpose == .dictation else { return }
        LocalModelResidencyCoordinator.shared.scheduleDictationIdleUnload(
            isMeetingCaptureActive: {
                await RecordingExclusivityCoordinator.shared.activeRecordingMode() == .meeting
            }
        )
    }
}

private extension RecordingManager {
    enum IncrementalCoordinatorKind {
        case dictation
        case meeting
    }

    func transcribeIncrementalSession(
        audioURL: URL,
        session: TranscriptionSessionSnapshot,
        coordinator: IncrementalTranscriptionCoordinator,
        coordinatorKind: IncrementalCoordinatorKind
    ) async {
        let checkpointID = await coordinator.checkpointID

        do {
            let transcription: CaptureArtifact
            var latencyBreakdown: DictationLatencyBreakdown?
            switch coordinatorKind {
            case .dictation:
                let finished = try await finishIncrementalDictationSession(
                    audioURL: audioURL,
                    session: session,
                    coordinator: coordinator
                )
                transcription = finished.artifact
                latencyBreakdown = DictationLatencyBreakdown(
                    incrementalFinishMs: finished.incrementalFinishMs,
                    finalizeMs: finished.finalizeMs,
                    deliveryMs: nil
                )
            case .meeting:
                transcription = try await finishIncrementalMeetingSession(
                    audioURL: audioURL,
                    session: session,
                    coordinator: coordinator
                )
            }
            let deliveryStart = Date()
            finishSuccessfulTranscription(transcription, session: session, latencyBreakdown: latencyBreakdown)
            if case .dictation = coordinatorKind {
                let deliveryMs = Int(Date().timeIntervalSince(deliveryStart) * 1000)
                AppLogger.info(
                    "Dictation latency breakdown",
                    category: .performance,
                    extra: [
                        "path": "incremental-final",
                        "sessionID": session.id.uuidString,
                        "deliveryMs": deliveryMs
                    ]
                )
            }
            if session.autoExportSummaries {
                await exportSummary(transcription: transcription)
            }
            clearCompletedMeetingState(sessionID: session.id)
        } catch is RemoteShortDictationSingleRequestError {
            // Short dictation with no dispatched window: one full-file
            // request, without failure noise. Zero extra requests were made.
            AppLogger.info(
                "Remote incremental dictation below window threshold; single full-file request",
                category: .recordingManager,
                extra: ["sessionID": session.id.uuidString]
            )
            teardownIncrementalCoordinator(for: coordinatorKind, coordinator: coordinator)
            let preparedAudio = await prepareAudioForTranscription(
                audioURL: audioURL,
                allowSilenceRemoval: shouldRemoveSilenceBeforeTranscription(for: session)
            )
            await transcribeRecording(
                audioURL: preparedAudio.transcriptionURL,
                session: session,
                cleanupAudioURL: preparedAudio.cleanupURL,
                transcriptionIDOverride: checkpointID,
                pipelinePath: "incremental-remote-short-single"
            )
        } catch {
            if await isShortSilentDictation(audioURL: audioURL, session: session, coordinator: coordinator) {
                skipSilentShortDictation(
                    audioURL: audioURL,
                    session: session,
                    coordinatorKind: coordinatorKind,
                    coordinator: coordinator
                )
                return
            }
            let fallbackReason = await coordinator.fallbackReason?.rawValue ?? "unknown"
            AppLogger.warning(
                "Incremental transcription failed during finalization; falling back to legacy full-file pipeline",
                category: .recordingManager,
                extra: [
                    "error": error.localizedDescription,
                    "reason": fallbackReason
                ]
            )
            teardownIncrementalCoordinator(for: coordinatorKind, coordinator: coordinator)
            let preparedAudio = await prepareAudioForTranscription(
                audioURL: audioURL,
                allowSilenceRemoval: shouldRemoveSilenceBeforeTranscription(for: session)
            )
            await transcribeRecording(
                audioURL: preparedAudio.transcriptionURL,
                session: session,
                cleanupAudioURL: preparedAudio.cleanupURL,
                transcriptionIDOverride: checkpointID,
                pipelinePath: "incremental->fallback-full-file",
                fallbackReason: fallbackReason
            )
        }
    }

    func teardownIncrementalCoordinator(
        for kind: IncrementalCoordinatorKind,
        coordinator: IncrementalTranscriptionCoordinator
    ) {
        switch kind {
        case .dictation:
            teardownIncrementalDictationSession(ownedBy: coordinator)
        case .meeting:
            teardownIncrementalMeetingSession(ownedBy: coordinator)
        }
    }

    /// Short accidental recordings (no VAD speech window, short silent audio)
    /// never reach remote transcription or AI post-processing.
    func isShortSilentDictation(
        audioURL: URL,
        session: TranscriptionSessionSnapshot,
        coordinator: IncrementalTranscriptionCoordinator
    ) async -> Bool {
        guard session.meeting.capturePurpose == .dictation else { return false }
        guard await !coordinator.hasAccumulatedContent else { return false }
        guard await coordinator.dispatchedRemoteWindowCount() == 0 else { return false }
        guard let audioDuration = await getAudioDuration(from: audioURL),
              audioDuration <= RemoteIncrementalDictationPolicy.shortSilenceSkipSeconds
        else { return false }
        let metrics = await Task.detached(priority: .utility) {
            RemoteWindowAudioSupport.silenceMetrics(for: audioURL)
        }.value
        guard let metrics else { return false }
        return metrics.peak < RemoteIncrementalDictationPolicy.silencePeakThreshold
            && metrics.rms < RemoteIncrementalDictationPolicy.silenceRMSThreshold
    }

    /// Resets a skipped silent recording cleanly: no transcription, no AI,
    /// no delivery, no error state.
    func skipSilentShortDictation(
        audioURL: URL,
        session: TranscriptionSessionSnapshot,
        coordinatorKind: IncrementalCoordinatorKind,
        coordinator: IncrementalTranscriptionCoordinator
    ) {
        AppLogger.info(
            "Skipped silent short recording without transcription",
            category: .recordingManager,
            extra: [
                "sessionID": session.id.uuidString,
                "audio": audioURL.lastPathComponent
            ]
        )
        teardownIncrementalCoordinator(for: coordinatorKind, coordinator: coordinator)
        unregisterTranscriptionSession(session.id)
        cancelEstimatedPostProcessingProgress(for: session.id)
        if shouldDriveSharedTranscriptionState(for: session.id) {
            meetingState = .idle
        }
        if currentMeeting?.id == session.id {
            currentMeeting?.state = .completed
        }
        scheduleStatusReset(sessionID: session.id)
        clearCompletedMeetingState(sessionID: session.id)
    }

    func finishSuccessfulTranscription(
        _ transcription: CaptureArtifact,
        session: TranscriptionSessionSnapshot,
        latencyBreakdown: DictationLatencyBreakdown? = nil
    ) {
        persistMeetingNotes(session.meetingNotesContent, forTranscription: transcription.id)
        if shouldDriveSharedTranscriptionState(for: session.id) {
            meetingState = .processing(.generatingOutput)
        }
        if currentMeeting?.id == session.id {
            currentMeeting?.state = .completed
        }
        TranscriptionDeliveryService.deliver(
            transcription: transcription,
            recordingSource: session.recordingSource,
            textPolicy: session.dictationTextHandlingPolicy,
            settings: session.deliverySettings ?? DeliverySettingsSnapshot()
        )
        logDictationLatency(transcription, session: session, path: "incremental-final", breakdown: latencyBreakdown)
        completeVisibleTranscription(success: true, sessionID: session.id)
        notifySuccess(for: transcription)
        scheduleStatusReset(sessionID: session.id)
        unregisterTranscriptionSession(session.id)
        cancelEstimatedPostProcessingProgress(for: session.id)
        if currentMeeting?.id == session.id {
            isStartingRecording = false
        }

        if foregroundTranscriptionSessionID == nil, !isRecording, !isStartingRecording {
            meetingState = .idle
        }
        scheduleDictationPostSessionUnloadIfNeeded(for: session.meeting.capturePurpose)
    }

    func clearCompletedMeetingState(sessionID: UUID) {
        clearMeetingNotesState(removePersistedValue: true, meetingID: sessionID)
        clearActiveTranscriptionSnapshot()
        guard currentMeeting?.id == sessionID else { return }
        currentMeeting = nil
        currentCapturePurpose = nil
        isMeetingMicrophoneEnabled = false
        postProcessingContext = nil
        postProcessingContextItems = []
        dictationSessionOutputLanguageOverride = nil
        dictationStartBundleIdentifier = nil
        dictationStartURL = nil
        activeStartTelemetry = nil
        clearPostProcessingReadinessWarning()
    }

    func handleStopRecordingError(
        _ error: Error,
        recordings: (mic: URL?, system: URL?),
        transcriptionSession: TranscriptionSessionSnapshot?,
        mergedAudioURL: URL?
    ) async {
        AppLogger.error("Failed to stop recording cleanly", category: .recordingManager, error: error)

        let retainedAudioURL = [recordings.mic, recordings.system, mergedAudioURL]
            .compactMap(\.self)
            .first { FileManager.default.fileExists(atPath: $0.path) }

        if let transcriptionSession, let retainedAudioURL {
            let audioDuration = await getAudioDuration(from: retainedAudioURL)
            await persistFailedTranscriptionAttempt(
                audioURL: retainedAudioURL,
                persistedAudioURL: retainedAudioURL,
                session: transcriptionSession,
                audioDuration: audioDuration,
                transcriptionIDOverride: transcriptionSession.id,
                error: error
            )
        }

        let ownsCurrentLifecycleState: Bool = if let transcriptionSession {
            currentMeeting?.id == transcriptionSession.id && !isRecording && !isStartingRecording
        } else {
            !isRecording && !isStartingRecording
        }
        guard ownsCurrentLifecycleState else {
            AppLogger.warning(
                "Retained recording audio after a stale stop-finalization failure",
                category: .recordingManager
            )
            if let transcriptionSession {
                unregisterTranscriptionSession(transcriptionSession.id)
            }
            return
        }

        await cancelIncrementalTranscriptionSessionsIfNeeded()
        await setMicAudioURL(nil)
        await setSystemAudioURL(nil)
        await setMergedAudioURL(nil)
        await resetRecordingLifecycleState(
            error: error,
            transcriptionID: transcriptionSession?.id
        )
        scheduleDictationPostSessionUnloadIfNeeded(for: transcriptionSession?.meeting.capturePurpose)
    }
}

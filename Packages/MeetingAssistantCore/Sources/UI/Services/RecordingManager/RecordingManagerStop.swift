import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

// MARK: - Recording Stop and Cancellation

public extension RecordingManager {
    /// Stop recording and optionally transcribe.
    func stopRecording() async {
        await stopRecording(transcribe: true)
    }

    // swiftlint:disable:next function_body_length
    func stopRecording(transcribe: Bool = true) async {
        cancelAutomaticMeetingRecordingStop()
        var transcriptionSession: TranscriptionSessionSnapshot?
        var mergedAudioURL: URL?
        var incrementalDictationCoordinator: IncrementalTranscriptionCoordinator?
        var incrementalMeetingCoordinator: IncrementalTranscriptionCoordinator?
        await lifecycleCoordinator.stop(
            isRecording: isRecording,
            transcribe: transcribe,
            operations: lifecycleOperations,
            actions: RecordingLifecycleCoordinator.StopActions(
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

        let capturePurpose = currentCapturePurpose
        cancelAutomaticMeetingRecordingStop()
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
        let session = currentMeeting.map(makeTranscriptionSessionSnapshot)
        clearActiveTranscriptionSnapshot()

        if transcribe, let session {
            registerTranscriptionSession(session.id, foreground: true)
            meetingState = .processing(.transcribing)
            currentMeeting?.state = .processing(.transcribing)
        } else {
            meetingState = .idle
            currentMeeting?.state = .completed
        }

        return session
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
            let transcription: Transcription = switch coordinatorKind {
            case .dictation:
                try await finishIncrementalDictationSession(
                    audioURL: audioURL,
                    session: session,
                    coordinator: coordinator
                )
            case .meeting:
                try await finishIncrementalMeetingSession(
                    audioURL: audioURL,
                    session: session,
                    coordinator: coordinator
                )
            }
            finishSuccessfulTranscription(transcription, session: session)
            if session.autoExportSummaries {
                await exportSummary(transcription: transcription)
            }
            clearCompletedMeetingState(sessionID: session.id)
        } catch {
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

    func finishSuccessfulTranscription(_ transcription: Transcription, session: TranscriptionSessionSnapshot) {
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

        let ownsCurrentLifecycleState: Bool = if let transcriptionSession {
            currentMeeting?.id == transcriptionSession.id && !isRecording && !isStartingRecording
        } else {
            !isRecording && !isStartingRecording
        }
        guard ownsCurrentLifecycleState else {
            var urls = [recordings.mic, recordings.system].compactMap(\.self)
            if let mergedAudioURL {
                urls.append(mergedAudioURL)
            }
            storage.cleanupTemporaryFiles(urls: Array(Set(urls)))
            return
        }

        await cleanupTemporaryFiles(additionalURLs: [recordings.mic, recordings.system].compactMap(\.self))
        if let mergedURL = await getMergedAudioURL() {
            try? FileManager.default.removeItem(at: mergedURL)
            await setMergedAudioURL(nil)
        }
        await cancelIncrementalTranscriptionSessionsIfNeeded()
        await resetRecordingLifecycleState(
            error: error,
            transcriptionID: transcriptionSession?.id
        )
        scheduleDictationPostSessionUnloadIfNeeded(for: transcriptionSession?.meeting.capturePurpose)
    }
}

import AVFoundation
import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

extension RecordingManager {
    func shouldUseIncrementalMeetingCapture(
        purpose: CapturePurpose,
        source: RecordingSource
    ) -> Bool {
        guard AppSettingsStore.shared.isMeetingTranscriptionEnabled else { return false }
        guard transcriptionClient is any TranscriptionServiceFinalDiarization else { return false }
        let config = IncrementalCaptureSupportConfig(
            expectedPurpose: .meeting,
            expectedSource: .all,
            executionMode: .meeting
        )
        return supportsIncrementalCapture(config, actualPurpose: purpose, actualSource: source)
    }

    func prepareIncrementalMeetingSessionIfNeeded(
        meeting: Meeting,
        purpose: CapturePurpose,
        source: RecordingSource
    ) async throws {
        guard shouldUseIncrementalMeetingCapture(purpose: purpose, source: source) else {
            teardownIncrementalMeetingSession()
            return
        }

        guard let recorder = concreteMicRecorder else { return }
        let transcriptionClientBox = UncheckedTranscriptionServiceBox(
            transcriptionClient,
            configuration: activeTranscriptionConfiguration
        )

        let coordinator = IncrementalTranscriptionCoordinator(
            transcriptionID: meeting.id,
            meeting: meeting,
            inputSource: resolveInputSourceLabel(for: meeting, recordingSource: source),
            storage: storage,
            transcriptionClientBox: transcriptionClientBox,
            voiceActivityKernel: audioKernelProvider.makeVoiceActivityKernel(),
            callbacks: .init(
                onProcessedDurationChanged: { [weak self] processedDuration in
                    Task { @MainActor [weak self] in
                        self?.transcriptionStatus.updateProgress(
                            phase: .processing,
                            processedSeconds: processedDuration
                        )
                    }
                }
            ),
            fallbackLogMessage: "Meeting incremental transcription degraded; full-file fallback required"
        )

        installIncrementalBufferForwarder(
            on: recorder,
            handler: { bufferBox in
                await coordinator.append(bufferBox: bufferBox)
            },
            onLoadStateChanged: { isHighLoad in
                Task {
                    await coordinator.setHighLoadMode(isHighLoad)
                }
            }
        )

        do {
            try await coordinator.start()
            incrementalMeetingCoordinator = coordinator
        } catch {
            clearIncrementalBufferForwarder(on: recorder)
            incrementalMeetingCoordinator = nil
            throw error
        }
    }

    func finishIncrementalMeetingSession(
        audioURL: URL,
        session: TranscriptionSessionSnapshot,
        coordinator: IncrementalTranscriptionCoordinator? = nil
    ) async throws -> Transcription {
        guard let coordinator = coordinator ?? incrementalMeetingCoordinator else {
            throw TranscriptionError.transcriptionFailed("Missing incremental meeting session")
        }

        let diarizationEnabled = shouldEnableDiarization(
            for: session.meeting,
            capturePurposeOverride: session.meeting.capturePurpose
        )
        let finalDiarizationServiceBox = (transcriptionClient as? any TranscriptionServiceFinalDiarization)
            .map(UncheckedFinalDiarizationServiceBox.init)

        let audioDuration = await beginIncrementalFinalizationUI(
            audioURL: audioURL,
            sessionID: session.id
        )

        let result = try await coordinator.finish(
            audioURL: audioURL,
            diarizationEnabled: diarizationEnabled,
            finalDiarizationServiceBox: finalDiarizationServiceBox
        )
        AppLogger.info(
            "Selected transcription pipeline",
            category: .recordingManager,
            extra: [
                "path": "incremental-final",
                "sessionID": session.id.uuidString,
                "capturePurpose": session.meeting.capturePurpose.rawValue
            ]
        )
        let transcription = try await finalizeIncrementalPreparedResponse(
            response: result.response,
            checkpointID: result.checkpointID,
            session: session,
            audioDuration: audioDuration,
            transcriptionDuration: result.wallClockDuration
        )
        teardownIncrementalMeetingSession(ownedBy: coordinator)
        return transcription
    }

    func teardownIncrementalMeetingSession(ownedBy coordinator: IncrementalTranscriptionCoordinator) {
        guard incrementalMeetingCoordinator === coordinator else { return }
        teardownIncrementalMeetingSession()
    }

    func teardownIncrementalMeetingSession() {
        guard incrementalMeetingCoordinator != nil else { return }
        if let recorder = concreteMicRecorder {
            clearIncrementalBufferForwarder(on: recorder)
        }
        incrementalMeetingCoordinator = nil
    }

    func cancelIncrementalMeetingSessionIfNeeded() async {
        if let incrementalMeetingCoordinator {
            await incrementalMeetingCoordinator.cancelAndDiscard()
        }
        teardownIncrementalMeetingSession()
    }

    func cancelIncrementalTranscriptionSessionsIfNeeded() async {
        await cancelIncrementalDictationSessionIfNeeded()
        await cancelIncrementalMeetingSessionIfNeeded()
        cancelDeferredIncrementalWarmup()
    }
}

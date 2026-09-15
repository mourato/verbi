import AVFoundation
import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

extension RecordingManager {
    func shouldUseIncrementalDictationCapture(
        purpose: CapturePurpose,
        source: RecordingSource
    ) -> Bool {
        let config = IncrementalCaptureSupportConfig(
            expectedPurpose: .dictation,
            expectedSource: .microphone,
            executionMode: .dictation
        )
        return supportsIncrementalCapture(config, actualPurpose: purpose, actualSource: source)
    }

    func prepareIncrementalDictationSessionIfNeeded(
        meeting: Meeting,
        purpose: CapturePurpose,
        source: RecordingSource
    ) async throws {
        guard shouldUseIncrementalDictationCapture(purpose: purpose, source: source) else {
            teardownIncrementalDictationSession()
            return
        }

        guard let recorder = concreteMicRecorder else { return }
        let transcriptionClientBox = UncheckedTranscriptionServiceBox(
            transcriptionClient,
            configuration: activeTranscriptionConfiguration
        )

        let holdBuffersUntilASRReady = shouldHoldDictationBuffersUntilASRReady()
        let asrWarmup = makeDictationASRWarmupHandler(holdBuffersUntilASRReady: holdBuffersUntilASRReady)

        let coordinator = makeIncrementalDictationCoordinator(
            meeting: meeting,
            source: source,
            transcriptionClientBox: transcriptionClientBox,
            holdBuffersUntilASRReady: holdBuffersUntilASRReady,
            asrWarmup: asrWarmup
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
            incrementalDictationCoordinator = coordinator
        } catch {
            clearIncrementalBufferForwarder(on: recorder)
            incrementalDictationCoordinator = nil
            throw error
        }
    }

    func finishIncrementalDictationSession(
        audioURL: URL,
        session: TranscriptionSessionSnapshot,
        coordinator: IncrementalTranscriptionCoordinator? = nil
    ) async throws -> Transcription {
        guard let coordinator = coordinator ?? incrementalDictationCoordinator else {
            throw TranscriptionError.transcriptionFailed("Missing incremental dictation session")
        }

        let audioDuration = await beginIncrementalFinalizationUI(
            audioURL: audioURL,
            sessionID: session.id
        )

        let result = try await coordinator.finish(
            audioURL: audioURL,
            diarizationEnabled: false,
            finalDiarizationServiceBox: nil
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
        teardownIncrementalDictationSession(ownedBy: coordinator)
        return transcription
    }

    func teardownIncrementalDictationSession(ownedBy coordinator: IncrementalTranscriptionCoordinator) {
        guard incrementalDictationCoordinator === coordinator else { return }
        teardownIncrementalDictationSession()
    }

    func teardownIncrementalDictationSession() {
        guard incrementalDictationCoordinator != nil else {
            transcriptionStatus.updateLivePreviewText("")
            return
        }
        if let recorder = concreteMicRecorder {
            clearIncrementalBufferForwarder(on: recorder)
        }
        incrementalDictationCoordinator = nil
        transcriptionStatus.updateLivePreviewText("")
    }

    func cancelIncrementalDictationSessionIfNeeded() async {
        if let incrementalDictationCoordinator {
            await incrementalDictationCoordinator.cancelAndDiscard()
        }
        teardownIncrementalDictationSession()
    }

    private func makeIncrementalDictationCoordinator(
        meeting: Meeting,
        source: RecordingSource,
        transcriptionClientBox: UncheckedTranscriptionServiceBox,
        holdBuffersUntilASRReady: Bool,
        asrWarmup: (@Sendable () async -> Void)?
    ) -> IncrementalTranscriptionCoordinator {
        IncrementalTranscriptionCoordinator(
            transcriptionID: meeting.id,
            meeting: meeting,
            inputSource: resolveInputSourceLabel(for: meeting, recordingSource: source),
            storage: storage,
            transcriptionClientBox: transcriptionClientBox,
            voiceActivityKernel: audioKernelProvider.makeVoiceActivityKernel(),
            callbacks: .init(
                onPreviewTextChanged: { [weak self] previewText in
                    Task { @MainActor [weak self] in
                        self?.transcriptionStatus.updateLivePreviewText(previewText)
                    }
                },
                onProcessedDurationChanged: { [weak self] (processedDuration: Double) in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        transcriptionStatus.updateProgress(
                            phase: .processing,
                            processedSeconds: processedDuration
                        )
                    }
                }
            ),
            fallbackLogMessage: "Dictation incremental transcription degraded; full-file fallback required",
            holdBuffersUntilASRReady: holdBuffersUntilASRReady,
            asrWarmup: asrWarmup
        )
    }
}

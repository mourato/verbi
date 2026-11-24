import AVFoundation
import Foundation
import VerbiCoreAI
import VerbiCoreAudio
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

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
        meeting: CaptureSession,
        purpose: CapturePurpose,
        source: RecordingSource
    ) async throws {
        guard shouldUseIncrementalDictationCapture(purpose: purpose, source: source) else {
            teardownIncrementalDictationSession()
            return
        }

        guard let recorder = concreteDictationRecorder else { return }
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
    ) async throws -> FinishedIncrementalDictation {
        guard let coordinator = coordinator ?? incrementalDictationCoordinator else {
            throw TranscriptionError.transcriptionFailed("Missing incremental dictation session")
        }

        let audioDuration = await beginIncrementalFinalizationUI(
            audioURL: audioURL,
            sessionID: session.id
        )

        let finishStart = Date()
        let result = try await coordinator.finish(
            audioURL: audioURL,
            diarizationEnabled: false,
            finalDiarizationServiceBox: nil
        )
        let finishElapsed = max(0, Date().timeIntervalSince(finishStart))
        let incrementalFinishMs = Int(finishElapsed * 1000)
        let isRemoteSession = await coordinator.isRemoteSession
        AppLogger.info(
            "Selected transcription pipeline",
            category: .recordingManager,
            extra: [
                "path": "incremental-final",
                "sessionID": session.id.uuidString,
                "capturePurpose": session.meeting.capturePurpose.rawValue
            ]
        )
        let finalizeStart = Date()
        let transcription = try await finalizeIncrementalPreparedResponse(
            response: result.response,
            checkpointID: result.checkpointID,
            session: session,
            audioDuration: audioDuration,
            transcriptionDuration: isRemoteSession ? finishElapsed : result.wallClockDuration
        )
        let finalizeMs = Int(Date().timeIntervalSince(finalizeStart) * 1000)
        teardownIncrementalDictationSession(ownedBy: coordinator)
        return FinishedIncrementalDictation(artifact: transcription, incrementalFinishMs: incrementalFinishMs, finalizeMs: finalizeMs)
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
        if let recorder = concreteDictationRecorder {
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

    func isShortSilentDictation(
        audioURL: URL,
        session: TranscriptionSessionSnapshot,
        coordinator: IncrementalTranscriptionCoordinator
    ) async -> Bool {
        guard await isEligibleForRemoteSilenceSkip(session: session, coordinator: coordinator) else {
            return false
        }
        return await isShortSilentAudioFile(at: audioURL)
    }

    private func isEligibleForRemoteSilenceSkip(
        session: TranscriptionSessionSnapshot,
        coordinator: IncrementalTranscriptionCoordinator
    ) async -> Bool {
        guard session.meeting.capturePurpose == .dictation else { return false }
        let isRemote = await coordinator.isRemoteSession
        let hasContent = await coordinator.hasAccumulatedContent
        let dispatched = await coordinator.dispatchedRemoteWindowCount()
        return isRemote && !hasContent && dispatched == 0
    }

    private func isShortSilentAudioFile(at audioURL: URL) async -> Bool {
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

    private func makeIncrementalDictationCoordinator(
        meeting: CaptureSession,
        source: RecordingSource,
        transcriptionClientBox: UncheckedTranscriptionServiceBox,
        holdBuffersUntilASRReady: Bool,
        asrWarmup: (@Sendable () async -> Void)?
    ) -> IncrementalTranscriptionCoordinator {
        let isRemote = activeTranscriptionConfiguration
            .flatMap { TranscriptionProvider(rawValue: $0.providerID) }
            .map(\.usesRemoteInference) ?? false
        let previewCallback: (@Sendable (String) -> Void)? = if isRemote {
            nil
        } else {
            { [weak self] previewText in
                Task { @MainActor [weak self] in
                    self?.transcriptionStatus.updateLivePreviewText(previewText)
                }
            }
        }
        return IncrementalTranscriptionCoordinator(
            transcriptionID: meeting.id,
            meeting: meeting,
            inputSource: resolveInputSourceLabel(for: meeting, recordingSource: source),
            storage: storage,
            transcriptionClientBox: transcriptionClientBox,
            voiceActivityKernel: audioKernelProvider.makeVoiceActivityKernel(),
            callbacks: .init(
                onPreviewTextChanged: previewCallback,
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
            asrWarmup: asrWarmup,
            isRemote: isRemote,
            suppressLivePreview: isRemote
        )
    }
}

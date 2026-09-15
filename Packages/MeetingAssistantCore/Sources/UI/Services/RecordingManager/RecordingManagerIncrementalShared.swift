import AVFoundation
import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import os.lock

extension RecordingManager {
    struct IncrementalCaptureSupportConfig {
        let expectedPurpose: CapturePurpose
        let expectedSource: RecordingSource
        let executionMode: TranscriptionExecutionMode
    }

    final class SendableIncrementalAudioBufferBox: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer

        init(buffer: AVAudioPCMBuffer) {
            self.buffer = buffer
        }
    }

    final class UncheckedTranscriptionServiceBox: @unchecked Sendable {
        @MainActor private let value: any TranscriptionService
        @MainActor private let configuration: DomainTranscriptionRequestConfiguration?

        @MainActor init(_ value: any TranscriptionService, configuration: DomainTranscriptionRequestConfiguration? = nil) {
            self.value = value
            self.configuration = configuration
        }

        @MainActor
        func transcribe(samples: [Float]) async throws -> TranscriptionResponse {
            if let configuration {
                return try await value.transcribe(
                    samples: samples,
                    configuration: configuration
                )
            }
            return try await value.transcribe(samples: samples)
        }
    }

    final class UncheckedFinalDiarizationServiceBox: @unchecked Sendable {
        @MainActor private let value: any TranscriptionServiceFinalDiarization

        @MainActor init(_ value: any TranscriptionServiceFinalDiarization) {
            self.value = value
        }

        @MainActor
        func diarize(audioURL: URL) async throws -> [SpeakerTimelineSegment] {
            try await value.diarize(audioURL: audioURL)
        }

        @MainActor
        func assignSpeakers(
            to segments: [Transcription.Segment],
            using speakerTimeline: [SpeakerTimelineSegment]
        ) -> [Transcription.Segment] {
            value.assignSpeakers(to: segments, using: speakerTimeline)
        }
    }

    final class IncrementalBufferForwarder: @unchecked Sendable {
        private enum PressureConstants {
            static let highPendingBufferThreshold = 7
            static let lowPendingBufferThreshold = 2
        }

        private struct PressureState {
            var pendingBufferCount = 0
            var isHighLoad = false
        }

        private final class ContinuationStorage: @unchecked Sendable {
            private let lock = OSAllocatedUnfairLock<AsyncStream<SendableIncrementalAudioBufferBox>.Continuation?>(initialState: nil)

            func set(_ continuation: AsyncStream<SendableIncrementalAudioBufferBox>.Continuation?) {
                lock.withLock { $0 = continuation }
            }

            func yield(_ buffer: AVAudioPCMBuffer) {
                let bufferBox = SendableIncrementalAudioBufferBox(buffer: buffer)
                _ = lock.withLock { $0?.yield(bufferBox) }
            }

            func finishAndClear() {
                lock.withLock { continuation in
                    continuation?.finish()
                    continuation = nil
                }
            }
        }

        private let continuationStorage = ContinuationStorage()
        private let pressureLock = OSAllocatedUnfairLock(initialState: PressureState())
        private let onLoadStateChanged: (@Sendable (Bool) -> Void)?
        private var processingTask: Task<Void, Never>?

        init(
            handler: @escaping @Sendable (SendableIncrementalAudioBufferBox) async -> Void,
            onLoadStateChanged: (@Sendable (Bool) -> Void)? = nil
        ) {
            self.onLoadStateChanged = onLoadStateChanged

            let stream = AsyncStream<SendableIncrementalAudioBufferBox> { continuation in
                continuationStorage.set(continuation)
            }

            processingTask = Task(priority: .userInitiated) {
                for await bufferBox in stream {
                    await handler(bufferBox)
                    emitLoadTransitionIfNeeded {
                        $0.pendingBufferCount = max(0, $0.pendingBufferCount - 1)
                    }
                }
            }
        }

        deinit {
            stop()
        }

        func enqueue(_ buffer: AVAudioPCMBuffer) {
            emitLoadTransitionIfNeeded {
                $0.pendingBufferCount += 1
            }
            continuationStorage.yield(buffer)
        }

        func stop() {
            continuationStorage.finishAndClear()
            processingTask?.cancel()
            processingTask = nil

            emitLoadTransitionIfNeeded {
                $0.pendingBufferCount = 0
            }
        }

        private func emitLoadTransitionIfNeeded(_ mutate: @Sendable (inout PressureState) -> Void) {
            let transition = pressureLock.withLock { state -> Bool? in
                mutate(&state)

                let nextIsHighLoad: Bool = if state.isHighLoad {
                    state.pendingBufferCount > PressureConstants.lowPendingBufferThreshold
                } else {
                    state.pendingBufferCount >= PressureConstants.highPendingBufferThreshold
                }

                guard nextIsHighLoad != state.isHighLoad else {
                    return nil
                }

                state.isHighLoad = nextIsHighLoad
                return nextIsHighLoad
            }

            if let transition {
                onLoadStateChanged?(transition)
            }
        }
    }

    func supportsIncrementalCapture(
        _ config: IncrementalCaptureSupportConfig,
        actualPurpose: CapturePurpose,
        actualSource: RecordingSource
    ) -> Bool {
        guard actualPurpose == config.expectedPurpose, actualSource == config.expectedSource else { return false }
        guard let recorder = concreteMicRecorder else { return false }
        guard recorder === AudioRecorder.shared else { return false }
        guard let configuration = activeTranscriptionConfiguration,
              let provider = TranscriptionProvider(rawValue: configuration.providerID)
        else { return false }
        return transcriptionClient.supportsIncrementalTranscription(
            selection: .init(provider: provider, selectedModel: configuration.modelID)
        )
    }

    func runDictationASRWarmupForReadyGate() async {
        guard let configuration = activeTranscriptionConfiguration,
              let transcriptionClient = transcriptionClient as? TranscriptionClient
        else {
            return
        }
        if transcriptionClient.isLocalASRReady(for: configuration.modelID) {
            return
        }
        try? await transcriptionClient.warmupModel(for: .dictation, configuration: configuration)
    }

    func shouldHoldDictationBuffersUntilASRReady() -> Bool {
        guard shouldEagerWarmupLocalASRForDictation(),
              let modelID = activeTranscriptionConfiguration?.modelID,
              let transcriptionClient = transcriptionClient as? TranscriptionClient
        else {
            return false
        }
        return !transcriptionClient.isLocalASRReady(for: modelID)
    }

    func makeDictationASRWarmupHandler(
        holdBuffersUntilASRReady: Bool
    ) -> (@Sendable () async -> Void)? {
        guard holdBuffersUntilASRReady else {
            return nil
        }
        return { [weak self] in
            await self?.runDictationASRWarmupForReadyGate()
        }
    }

    func warmupIncrementalTranscriptionIfNeeded() {
        guard let transcriptionClient = transcriptionClient as? TranscriptionClient else { return }
        transcriptionClient.warmupModelIfNeededInBackground(for: .meeting, configuration: activeTranscriptionConfiguration)
    }

    func shouldEagerWarmupLocalASRForDictation() -> Bool {
        guard currentCapturePurpose == .dictation else { return false }
        guard let configuration = activeTranscriptionConfiguration,
              let provider = TranscriptionProvider(rawValue: configuration.providerID)
        else { return false }
        return provider == .local
    }

    func scheduleEagerDictationWarmupIfNeeded(meetingID: UUID) {
        guard shouldEagerWarmupLocalASRForDictation() else { return }

        deferredIncrementalWarmupTask?.cancel()
        deferredIncrementalWarmupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard !Task.isCancelled else { return }
            guard isRecording, currentMeeting?.id == meetingID else { return }
            guard let transcriptionClient = transcriptionClient as? TranscriptionClient else { return }
            transcriptionClient.warmupModelIfNeededInBackground(
                for: .dictation,
                configuration: activeTranscriptionConfiguration
            )
        }
    }

    func scheduleDeferredIncrementalWarmupIfNeeded(meetingID: UUID) {
        guard incrementalMeetingCoordinator != nil else { return }

        deferredIncrementalWarmupTask?.cancel()

        deferredIncrementalWarmupTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Constants.deferredIncrementalWarmupDelay)
            guard let self else { return }
            guard !Task.isCancelled else { return }
            guard isRecording, currentMeeting?.id == meetingID else { return }
            warmupIncrementalTranscriptionIfNeeded()
        }
    }

    func cancelDeferredIncrementalWarmup() {
        deferredIncrementalWarmupTask?.cancel()
        deferredIncrementalWarmupTask = nil
    }

    func clearIncrementalBufferForwarder(on recorder: AudioRecorder?) {
        recorder?.onMixedAudioBuffer = nil
        incrementalBufferForwarder?.stop()
        incrementalBufferForwarder = nil
    }

    func installIncrementalBufferForwarder(
        on recorder: AudioRecorder,
        handler: @escaping @Sendable (SendableIncrementalAudioBufferBox) async -> Void,
        onLoadStateChanged: (@Sendable (Bool) -> Void)? = nil
    ) {
        clearIncrementalBufferForwarder(on: recorder)

        let forwarder = IncrementalBufferForwarder(
            handler: handler,
            onLoadStateChanged: onLoadStateChanged
        )
        incrementalBufferForwarder = forwarder
        recorder.onMixedAudioBuffer = { [weak forwarder] buffer in
            forwarder?.enqueue(buffer)
        }
    }

    func beginIncrementalFinalizationUI(
        audioURL: URL,
        sessionID: UUID
    ) async -> Double? {
        let audioDuration = await getAudioDuration(from: audioURL)
        beginVisibleTranscriptionStatus(audioDuration: audioDuration, sessionID: sessionID)
        updateVisibleTranscriptionProgress(
            phase: .processing,
            percentage: Constants.processingProgress,
            sessionID: sessionID
        )
        return audioDuration
    }

    func finalizeIncrementalPreparedResponse(
        response: DomainTranscriptionResponse,
        checkpointID: UUID,
        session: TranscriptionSessionSnapshot,
        audioDuration: Double?,
        transcriptionDuration: Double
    ) async throws -> Transcription {
        let meetingEntity = makeMeetingEntity(meeting: session.meeting, audioDuration: audioDuration)
        guard var config = session.useCaseConfig else {
            throw TranscriptionError.transcriptionFailed("Missing transcription operation configuration.")
        }
        config.postProcessingContext = session.postProcessingContext
        config.postProcessingContextItems = session.postProcessingContextItems
        let transcriptionIdentity = session.transcriptionConfiguration.flatMap { configuration in
            TranscriptionProvider(rawValue: configuration.providerID)?.modelPerformanceIdentity(modelID: configuration.modelID)
        } ?? ModelPerformanceIdentityResolver.unknown()
        let transcriptionCompletedAt = Date()
        let transcriptionStartedAt = transcriptionCompletedAt.addingTimeInterval(-max(0, transcriptionDuration))

        if shouldDriveSharedTranscriptionState(for: session.id) {
            meetingState = .processing(.generatingOutput)
        }

        let transcriptionEntity = try await transcribeAudioUseCase.finalizePreparedResponse(
            response: response,
            transcriptionID: checkpointID,
            meeting: meetingEntity,
            transcriptionIdentity: transcriptionIdentity,
            inputSource: resolveInputSourceLabel(for: session.meeting, recordingSource: session.recordingSource),
            contextItems: config.postProcessingContextItems,
            vocabularyReplacementRules: session.vocabularySnapshot.replacementRules,
            vocabularyTerms: session.vocabularySnapshot.terms,
            transcriptionConfiguration: session.transcriptionConfiguration,
            applyPostProcessing: config.applyPostProcessing,
            postProcessingPrompt: config.postProcessingPrompt,
            defaultPostProcessingPrompt: config.defaultPostProcessingPrompt,
            postProcessingIdentity: config.postProcessingIdentity,
            postProcessingSelection: config.postProcessingSelection.map {
                DomainPostProcessingSelection(
                    providerID: $0.provider.rawValue,
                    modelID: $0.selectedModel,
                    registrationID: $0.registrationID
                )
            },
            postProcessingConfiguration: config.postProcessingConfiguration,
            postProcessingFailureReason: config.postProcessingFailureReason,
            autoDetectMeetingType: config.autoDetectMeetingType,
            availablePrompts: config.availablePrompts,
            postProcessingContext: config.postProcessingContext,
            postProcessingSystemPrompt: config.postProcessingSystemPrompt,
            kernelMode: config.kernelMode,
            dictationStructuredPostProcessingEnabled: config.dictationStructuredPostProcessingEnabled,
            transcriptionDuration: transcriptionDuration,
            transcriptionStartedAt: transcriptionStartedAt,
            transcriptionCompletedAt: transcriptionCompletedAt,
            onPhaseChange: { [weak self] phase in
                Task { @MainActor [weak self] in
                    self?.handleUseCasePhaseChange(phase, meeting: session.meeting, sessionID: session.id)
                }
            }
        )

        return convertToModel(
            transcriptionEntity,
            audioDuration: audioDuration,
            transcriptionStart: session.meeting.startTime
        )
    }
}

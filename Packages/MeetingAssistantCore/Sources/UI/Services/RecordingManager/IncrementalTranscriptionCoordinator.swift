@preconcurrency import AVFoundation
import Foundation
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
@preconcurrency import MeetingAssistantCoreInfrastructure

// swiftlint:disable type_name
actor IncrementalTranscriptionCoordinator {
    struct FinalizedResult {
        let response: DomainTranscriptionResponse
        let checkpointID: UUID
        let wallClockDuration: Double
    }

    struct Callbacks {
        var onPreviewTextChanged: (@Sendable (String) -> Void)?
        let onProcessedDurationChanged: @Sendable (Double) -> Void
    }

    private let core: IncrementalTranscriptionCoordinatorCore

    init(
        transcriptionID: UUID,
        meeting: Meeting,
        inputSource: String?,
        storage: any StorageService,
        transcriptionClientBox: RecordingManager.UncheckedTranscriptionServiceBox,
        voiceActivityKernel: any VoiceActivityKernel = RealtimeVoiceActivityWindowAssembler(),
        callbacks: Callbacks,
        fallbackLogMessage: String,
        holdBuffersUntilASRReady: Bool = false,
        asrWarmup: (@Sendable () async -> Void)? = nil,
    ) {
        core = IncrementalTranscriptionCoordinatorCore(
            configuration: .init(
                transcriptionID: transcriptionID,
                meeting: meeting,
                inputSource: inputSource,
                storage: storage,
                transcriptionClientBox: transcriptionClientBox,
                voiceActivityKernel: voiceActivityKernel,
                onPreviewTextChanged: callbacks.onPreviewTextChanged,
                onProcessedDurationChanged: callbacks.onProcessedDurationChanged,
                fallbackLogMessage: fallbackLogMessage,
                holdBuffersUntilASRReady: holdBuffersUntilASRReady,
                asrWarmup: asrWarmup,
            ),
        )
    }

    var checkpointID: UUID {
        get async {
            await core.checkpointID
        }
    }

    var requiresLegacyFallback: Bool {
        get async {
            await core.requiresLegacyFallback
        }
    }

    var fallbackError: Error? {
        get async {
            await core.fallbackError
        }
    }

    var fallbackReason: IncrementalTranscriptionFallbackReason? {
        get async {
            await core.fallbackReason
        }
    }

    func start() async throws {
        try await core.start()
    }

    func beginASRWarmupIfNeeded() async {
        await core.beginASRWarmupIfNeeded()
    }

    func append(bufferBox: RecordingManager.SendableIncrementalAudioBufferBox) async {
        await core.append(bufferBox: bufferBox)
    }

    func setHighLoadMode(_ isHighLoad: Bool) async {
        await core.setHighLoadMode(isHighLoad)
    }

    func setASRReady(_ ready: Bool) async {
        await core.setASRReady(ready)
    }

    func finish(
        audioURL: URL,
        diarizationEnabled: Bool,
        finalDiarizationServiceBox: RecordingManager.UncheckedFinalDiarizationServiceBox?,
    ) async throws -> FinalizedResult {
        try await core.finishAccumulation()

        var finalizedSegments = await core.currentSegments
        if diarizationEnabled {
            guard let finalDiarizationServiceBox else {
                let error = TranscriptionError.transcriptionFailed("Final diarization unsupported in current backend")
                await core.markForLegacyFallback(error, reason: .finalDiarizationFailed)
                throw error
            }

            do {
                let speakerTimeline = try await finalDiarizationServiceBox.diarize(audioURL: audioURL)
                let currentSegments = await core.currentSegments
                finalizedSegments = await finalDiarizationServiceBox.assignSpeakers(
                    to: currentSegments,
                    using: speakerTimeline,
                )
            } catch {
                await core.markForLegacyFallback(error, reason: .finalDiarizationFailed)
                throw error
            }
        }

        let response = try await core.buildFinalizedResponse(segmentsOverride: finalizedSegments)

        return await FinalizedResult(
            response: response,
            checkpointID: core.checkpointID,
            wallClockDuration: core.wallClockElapsedSeconds,
        )
    }

    func cancelAndDiscard() async {
        await core.cancelAndDiscard()
    }
}

// swiftlint:enable type_name

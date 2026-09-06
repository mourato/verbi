import AVFoundation
@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreAudio
@testable import MeetingAssistantCoreUI
import os
import XCTest

@MainActor
final class IncrementalReadyGateTests: XCTestCase {
    func testSetASRReady_FlipsReadinessWithoutAudioHardware() async throws {
        let coordinator = makeGatedCoordinator(asrWarmup: nil)

        try await coordinator.start()
        await coordinator.setASRReady(false)
        await coordinator.setASRReady(true)
    }

    func testAppend_WhileNotReady_HoldsThenFlushesInOrder() async throws {
        let storage = MockStorageService()
        let transcriptionClient = MockTranscriptionClient()
        transcriptionClient.mockText = "chunk"
        let transcriptionClientBox = RecordingManager.UncheckedTranscriptionServiceBox(transcriptionClient)
        let voiceKernel = ReadyGateStubVoiceActivityKernel()
        let coordinator = IncrementalTranscriptionCoordinator(
            transcriptionID: UUID(),
            meeting: makeMeeting(),
            inputSource: "microphone",
            storage: storage,
            transcriptionClientBox: transcriptionClientBox,
            voiceActivityKernel: voiceKernel,
            callbacks: .init(
                onPreviewTextChanged: { _ in },
                onProcessedDurationChanged: { _ in },
            ),
            fallbackLogMessage: "Dictation incremental transcription degraded; full-file fallback required",
            holdBuffersUntilASRReady: true,
            asrWarmup: {
                try? await Task.sleep(for: .seconds(30))
            },
        )

        try await coordinator.start()
        try await coordinator.append(
            bufferBox: RecordingManager.SendableIncrementalAudioBufferBox(
                buffer: makeBuffer(segments: [.tone(0.5, amplitude: 0.25)]),
            ),
        )
        try await coordinator.append(
            bufferBox: RecordingManager.SendableIncrementalAudioBufferBox(
                buffer: makeBuffer(segments: [.tone(0.5, amplitude: 0.25)]),
            ),
        )

        XCTAssertEqual(transcriptionClient.sampleTranscribeCallCount, 0)

        await coordinator.setASRReady(true)

        XCTAssertEqual(transcriptionClient.sampleTranscribeCallCount, 2)
        let requiresLegacyFallback = await coordinator.requiresLegacyFallback
        XCTAssertFalse(requiresLegacyFallback)
    }

    func testAppend_QueueOverflowBeforeReady_TriggersFallback() async throws {
        let storage = MockStorageService()
        let transcriptionClient = MockTranscriptionClient()
        let transcriptionClientBox = RecordingManager.UncheckedTranscriptionServiceBox(transcriptionClient)
        let coordinator = makeGatedCoordinator(
            storage: storage,
            transcriptionClientBox: transcriptionClientBox,
            asrWarmup: {
                try? await Task.sleep(for: .seconds(30))
            },
        )

        try await coordinator.start()
        try await coordinator.append(
            bufferBox: RecordingManager.SendableIncrementalAudioBufferBox(
                buffer: makeBuffer(segments: [.tone(2.0, amplitude: 0.25)]),
            ),
        )
        try await coordinator.append(
            bufferBox: RecordingManager.SendableIncrementalAudioBufferBox(
                buffer: makeBuffer(segments: [.tone(2.0, amplitude: 0.25)]),
            ),
        )

        let requiresLegacyFallback = await coordinator.requiresLegacyFallback
        let fallbackReason = await coordinator.fallbackReason

        XCTAssertTrue(requiresLegacyFallback)
        XCTAssertEqual(fallbackReason, .assemblerFailed)
        XCTAssertEqual(transcriptionClient.sampleTranscribeCallCount, 0)
    }

    func testFinish_WhileWarmupInFlight_DoesNotDeadlock() async throws {
        let storage = MockStorageService()
        let transcriptionClient = MockTranscriptionClient()
        transcriptionClient.mockText = "warm"
        let transcriptionClientBox = RecordingManager.UncheckedTranscriptionServiceBox(transcriptionClient)
        let coordinator = IncrementalTranscriptionCoordinator(
            transcriptionID: UUID(),
            meeting: makeMeeting(),
            inputSource: "microphone",
            storage: storage,
            transcriptionClientBox: transcriptionClientBox,
            callbacks: .init(
                onPreviewTextChanged: { _ in },
                onProcessedDurationChanged: { _ in },
            ),
            fallbackLogMessage: "Dictation incremental transcription degraded; full-file fallback required",
            holdBuffersUntilASRReady: true,
            asrWarmup: {
                try? await Task.sleep(for: .seconds(30))
            },
        )

        try await coordinator.start()
        await coordinator.beginASRWarmupIfNeeded()
        try await coordinator.append(
            bufferBox: RecordingManager.SendableIncrementalAudioBufferBox(
                buffer: makeBuffer(segments: [.tone(1.0, amplitude: 0.25)]),
            ),
        )

        let started = ContinuousClock.now
        let result = try await coordinator.finish(
            audioURL: URL(fileURLWithPath: "/tmp/dictation-ready-gate-test.wav"),
            diarizationEnabled: false,
            finalDiarizationServiceBox: nil,
        )
        let elapsed = started.duration(to: ContinuousClock.now)

        XCTAssertLessThan(elapsed, .seconds(5))
        XCTAssertFalse(result.response.text.isEmpty)
    }

    func testStart_DoesNotInvokeASRWarmupUntilBeginWarmup() async throws {
        let warmupStarted = OSAllocatedUnfairLock(initialState: false)
        let coordinator = makeGatedCoordinator {
            warmupStarted.withLock { $0 = true }
        }

        try await coordinator.start()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(warmupStarted.withLock { $0 })

        await coordinator.beginASRWarmupIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(warmupStarted.withLock { $0 })
    }

    func testHoldBuffersWithNilWarmup_OpensGateWithoutWarmup() async throws {
        let storage = MockStorageService()
        let transcriptionClient = MockTranscriptionClient()
        transcriptionClient.mockText = "chunk"
        let transcriptionClientBox = RecordingManager.UncheckedTranscriptionServiceBox(transcriptionClient)
        let voiceKernel = ReadyGateStubVoiceActivityKernel()
        let coordinator = IncrementalTranscriptionCoordinator(
            transcriptionID: UUID(),
            meeting: makeMeeting(),
            inputSource: "microphone",
            storage: storage,
            transcriptionClientBox: transcriptionClientBox,
            voiceActivityKernel: voiceKernel,
            callbacks: .init(
                onPreviewTextChanged: { _ in },
                onProcessedDurationChanged: { _ in },
            ),
            fallbackLogMessage: "Dictation incremental transcription degraded; full-file fallback required",
            holdBuffersUntilASRReady: true,
            asrWarmup: nil,
        )

        try await coordinator.start()
        await coordinator.beginASRWarmupIfNeeded()
        try await coordinator.append(
            bufferBox: RecordingManager.SendableIncrementalAudioBufferBox(
                buffer: makeBuffer(segments: [.tone(0.5, amplitude: 0.25)]),
            ),
        )

        XCTAssertEqual(transcriptionClient.sampleTranscribeCallCount, 1)
        let requiresLegacyFallback = await coordinator.requiresLegacyFallback
        XCTAssertFalse(requiresLegacyFallback)
    }

    private func makeGatedCoordinator(
        storage: MockStorageService = MockStorageService(),
        transcriptionClientBox: RecordingManager.UncheckedTranscriptionServiceBox? = nil,
        asrWarmup: (@Sendable () async -> Void)?,
    ) -> IncrementalTranscriptionCoordinator {
        let transcriptionClient = MockTranscriptionClient()
        let box = transcriptionClientBox ?? RecordingManager.UncheckedTranscriptionServiceBox(transcriptionClient)
        return IncrementalTranscriptionCoordinator(
            transcriptionID: UUID(),
            meeting: makeMeeting(),
            inputSource: "microphone",
            storage: storage,
            transcriptionClientBox: box,
            callbacks: .init(
                onPreviewTextChanged: { _ in },
                onProcessedDurationChanged: { _ in },
            ),
            fallbackLogMessage: "Dictation incremental transcription degraded; full-file fallback required",
            holdBuffersUntilASRReady: true,
            asrWarmup: asrWarmup,
        )
    }

    private func makeMeeting() -> Meeting {
        Meeting(
            app: .unknown,
            capturePurpose: .dictation,
            title: "Ready Gate Test",
            audioFilePath: "/tmp/dictation-ready-gate-test.wav",
        )
    }

    private func makeBuffer(segments: [ReadyGateSampleSegment], sampleRate: Double = 16_000) throws -> AVAudioPCMBuffer {
        let samples = segments.flatMap { segment in
            let sampleCount = Int(segment.duration * sampleRate)
            return (0..<sampleCount).map { frameIndex in
                segment.sample(at: frameIndex, sampleRate: sampleRate)
            }
        }

        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let frameCount = AVAudioFrameCount(samples.count)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData else {
            throw NSError(domain: "IncrementalReadyGateTests", code: 1)
        }

        for (index, sample) in samples.enumerated() {
            channelData[0][index] = sample
        }

        return buffer
    }
}

private actor ReadyGateStubVoiceActivityKernel: VoiceActivityKernel {
    private var nextWindowIndex = 0

    func setAdaptiveQualityMode(_: RealtimeVoiceActivityWindowAssembler.AdaptiveQualityMode) async {}

    func append(buffer: AVAudioPCMBuffer) async throws -> [RealtimeVoiceActivityWindowAssembler.Window] {
        let sampleRate = buffer.format.sampleRate
        let duration = sampleRate > 0 ? Double(buffer.frameLength) / sampleRate : 0
        let startTime = Double(nextWindowIndex) * duration
        nextWindowIndex += 1
        return [
            RealtimeVoiceActivityWindowAssembler.Window(
                startTime: startTime,
                endTime: startTime + duration,
                samples: [0.1, 0.2, 0.3],
            ),
        ]
    }

    func finish() async throws -> [RealtimeVoiceActivityWindowAssembler.Window] {
        []
    }
}

private struct ReadyGateSampleSegment {
    let duration: Double
    let amplitude: Float

    static func tone(_ duration: Double, amplitude: Float) -> ReadyGateSampleSegment {
        ReadyGateSampleSegment(duration: duration, amplitude: amplitude)
    }

    func sample(at frameIndex: Int, sampleRate: Double) -> Float {
        let angle = 2 * Double.pi * Double(frameIndex) * 220 / sampleRate
        return sin(Float(angle)) * amplitude
    }
}

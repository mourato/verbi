import AVFoundation
@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreUI
import XCTest

@MainActor
final class IncrementalDictationCoordinatorTests: XCTestCase {
    func testAppend_LongSpeechPersistsPartialCheckpointBeforeFinish() async throws {
        let storage = MockStorageService()
        let transcriptionClient = MockTranscriptionClient()
        let transcriptionClientBox = RecordingManager.UncheckedTranscriptionServiceBox(transcriptionClient)
        transcriptionClient.mockText = "partial"
        let previewRecorder = PreviewRecorder()
        let coordinator = IncrementalTranscriptionCoordinator(
            transcriptionID: UUID(),
            meeting: makeMeeting(),
            inputSource: "microphone",
            storage: storage,
            transcriptionClientBox: transcriptionClientBox,
            callbacks: .init(
                onPreviewTextChanged: { text in previewRecorder.values.append(text) },
                onProcessedDurationChanged: { _ in },
            ),
            fallbackLogMessage: "Dictation incremental transcription degraded; full-file fallback required",
        )

        try await coordinator.start()
        try await coordinator.append(
            bufferBox: RecordingManager.SendableIncrementalAudioBufferBox(
                buffer: makeBuffer(segments: [.tone(13.0, amplitude: 0.25)]),
            ),
        )

        XCTAssertGreaterThanOrEqual(storage.savedTranscriptions.count, 2)
        XCTAssertEqual(storage.savedTranscriptions[0].lifecycleState, .partial)
        XCTAssertTrue(storage.savedTranscriptions.contains(where: { $0.lifecycleState == .partial && !$0.rawText.isEmpty }))
        XCTAssertEqual(transcriptionClient.transcribeCallCount, 1)
        XCTAssertFalse(previewRecorder.values.isEmpty)

        let result = try await coordinator.finish(
            audioURL: URL(fileURLWithPath: "/tmp/dictation-test.wav"),
            diarizationEnabled: false,
            finalDiarizationServiceBox: nil,
        )
        XCTAssertEqual(result.response.text, "partial partial")
        XCTAssertEqual(storage.savedTranscriptions.last?.lifecycleState, .finalizing)
        XCTAssertEqual(transcriptionClient.transcribeCallCount, 2)
        XCTAssertGreaterThan(result.wallClockDuration, 0)
    }

    func testFinish_WhenTranscriptionFails_PersistsFailedCheckpoint() async throws {
        let storage = MockStorageService()
        let transcriptionClient = MockTranscriptionClient()
        let transcriptionClientBox = RecordingManager.UncheckedTranscriptionServiceBox(transcriptionClient)
        transcriptionClient.shouldFailTranscription = true
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
        )

        try await coordinator.start()
        try await coordinator.append(
            bufferBox: RecordingManager.SendableIncrementalAudioBufferBox(
                buffer: makeBuffer(segments: [.tone(1.0, amplitude: 0.25)]),
            ),
        )

        do {
            _ = try await coordinator.finish(
                audioURL: URL(fileURLWithPath: "/tmp/dictation-test.wav"),
                diarizationEnabled: false,
                finalDiarizationServiceBox: nil,
            )
            XCTFail("Expected finish to throw")
        } catch {}

        let requiresLegacyFallback = await coordinator.requiresLegacyFallback
        let fallbackReason = await coordinator.fallbackReason
        let fallbackError = await coordinator.fallbackError

        XCTAssertTrue(requiresLegacyFallback)
        XCTAssertEqual(fallbackReason, .windowTranscriptionFailed)
        XCTAssertNotNil(fallbackError)
        XCTAssertEqual(storage.savedTranscriptions.last?.lifecycleState, .finalizing)
    }

    func testFinish_WhenNoIncrementalTranscriptIsProduced_ThrowsAndPersistsFailedCheckpoint() async throws {
        let storage = MockStorageService()
        let transcriptionClient = MockTranscriptionClient()
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
        )

        try await coordinator.start()

        do {
            _ = try await coordinator.finish(
                audioURL: URL(fileURLWithPath: "/tmp/dictation-test.wav"),
                diarizationEnabled: false,
                finalDiarizationServiceBox: nil,
            )
            XCTFail("Expected finish to throw")
        } catch let error as TranscriptionError {
            guard case let .transcriptionFailed(message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(message, PostProcessingError.emptyTranscription.localizedDescription)
        }

        let requiresLegacyFallback = await coordinator.requiresLegacyFallback
        let fallbackReason = await coordinator.fallbackReason

        XCTAssertEqual(storage.savedTranscriptions.last?.lifecycleState, .finalizing)
        XCTAssertTrue(requiresLegacyFallback)
        XCTAssertEqual(fallbackReason, .emptyTranscript)
        XCTAssertEqual(transcriptionClient.transcribeCallCount, 0)
    }

    private func makeMeeting() -> CaptureSession {
        CaptureSession(
            app: .unknown,
            capturePurpose: .dictation,
            title: "Dictation Test",
            audioFilePath: "/tmp/dictation-test.wav",
        )
    }

    private func makeBuffer(segments: [CoordinatorSampleSegment], sampleRate: Double = 16_000) throws -> AVAudioPCMBuffer {
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
            throw NSError(domain: "IncrementalDictationCoordinatorTests", code: 1)
        }

        for (index, sample) in samples.enumerated() {
            channelData[0][index] = sample
        }

        return buffer
    }
}

private final class PreviewRecorder: @unchecked Sendable {
    var values: [String] = []
}

private struct CoordinatorSampleSegment {
    let duration: Double
    let amplitude: Float

    static func tone(_ duration: Double, amplitude: Float) -> CoordinatorSampleSegment {
        CoordinatorSampleSegment(duration: duration, amplitude: amplitude)
    }

    func sample(at frameIndex: Int, sampleRate: Double) -> Float {
        let angle = 2 * Double.pi * Double(frameIndex) * 220 / sampleRate
        return sin(Float(angle)) * amplitude
    }
}

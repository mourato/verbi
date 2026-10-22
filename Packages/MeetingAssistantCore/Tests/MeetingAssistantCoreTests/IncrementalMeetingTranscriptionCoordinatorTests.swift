import AVFoundation
@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreUI
import XCTest

@MainActor
final class IncrementalMeetingCoordinatorTests: XCTestCase {
    func testCheckpointPersistsNoSummaryOverrideWithMeeting() async throws {
        let storage = MockStorageService()
        let meeting = makeMeeting()
        let coordinator = IncrementalTranscriptionCoordinator(
            transcriptionID: meeting.id,
            meeting: meeting,
            inputSource: "system+microphone",
            storage: storage,
            transcriptionClientBox: RecordingManager.UncheckedTranscriptionServiceBox(MockTranscriptionClient()),
            callbacks: .init(onProcessedDurationChanged: { _ in }),
            fallbackLogMessage: "Full-file fallback required",
            executionProvenance: ExecutionProvenance(
                transcriptionRequest: nil,
                vocabularySnapshot: .empty,
                transcriptionModelIdentity: ModelPerformanceIdentityResolver.unknown(),
                skipPostProcessing: true
            )
        )
        try await coordinator.start()
        let checkpoint = try XCTUnwrap(storage.savedTranscriptions.last)
        let restored = try JSONDecoder().decode(CaptureArtifact.self, from: JSONEncoder().encode(checkpoint))
        XCTAssertEqual(restored.meeting.id, meeting.id)
        XCTAssertTrue(try XCTUnwrap(restored.executionProvenance).skipPostProcessing)
        await coordinator.cancelAndDiscard()
    }

    func testFinish_WithFinalDiarizationAssignsSpeakersAndPersistsFinalizingCheckpoint() async throws {
        let storage = MockStorageService()
        let transcriptionClient = MockTranscriptionClient()
        let transcriptionClientBox = RecordingManager.UncheckedTranscriptionServiceBox(transcriptionClient)
        let finalDiarizationServiceBox = RecordingManager.UncheckedFinalDiarizationServiceBox(transcriptionClient)
        transcriptionClient.mockText = "meeting partial"
        transcriptionClient.mockSegments = [
            CaptureArtifact.Segment(
                speaker: CaptureArtifact.unknownSpeaker,
                text: "meeting partial",
                startTime: 0,
                endTime: 1.0
            )
        ]
        transcriptionClient.mockSpeakerTimeline = [
            SpeakerTimelineSegment(
                speaker: "Speaker 1",
                startTime: 0,
                endTime: 10.0
            )
        ]

        let processedDurationRecorder = ProcessedDurationRecorder()
        let coordinator = IncrementalTranscriptionCoordinator(
            transcriptionID: UUID(),
            meeting: makeMeeting(),
            inputSource: "system+microphone",
            storage: storage,
            transcriptionClientBox: transcriptionClientBox,
            callbacks: .init(
                onProcessedDurationChanged: { processedDurationRecorder.values.append($0) }
            ),
            fallbackLogMessage: "Meeting incremental transcription degraded; full-file fallback required"
        )

        try await coordinator.start()
        try await coordinator.append(
            bufferBox: RecordingManager.SendableIncrementalAudioBufferBox(
                buffer: makeBuffer(segments: [.tone(1.0, amplitude: 0.25)])
            )
        )

        let result = try await coordinator.finish(
            audioURL: URL(fileURLWithPath: "/tmp/meeting-test.wav"),
            diarizationEnabled: true,
            finalDiarizationServiceBox: finalDiarizationServiceBox
        )

        XCTAssertEqual(transcriptionClient.fileTranscribeCallCount, 0)
        XCTAssertEqual(transcriptionClient.sampleTranscribeCallCount, 1)
        XCTAssertEqual(transcriptionClient.diarizeCallCount, 1)
        XCTAssertEqual(transcriptionClient.assignSpeakersCallCount, 1)
        let checkpointID = await coordinator.checkpointID

        XCTAssertEqual(storage.savedTranscriptions.first?.lifecycleState, .partial)
        XCTAssertNil(storage.savedTranscriptions.first?.executionProvenance)
        XCTAssertEqual(storage.savedTranscriptions.last?.lifecycleState, .finalizing)
        XCTAssertEqual(result.checkpointID, checkpointID)
        XCTAssertEqual(result.response.segments.map(\.speaker), ["Speaker 1"])
        XCTAssertEqual(result.response.text, "meeting partial")
        XCTAssertGreaterThan(result.wallClockDuration, 0)
        XCTAssertFalse(processedDurationRecorder.values.isEmpty)
    }

    func testFinish_WhenWindowTranscriptionFailsMarksFallbackAndPersistsFailedCheckpoint() async throws {
        let storage = MockStorageService()
        let transcriptionClient = MockTranscriptionClient()
        let transcriptionClientBox = RecordingManager.UncheckedTranscriptionServiceBox(transcriptionClient)
        let finalDiarizationServiceBox = RecordingManager.UncheckedFinalDiarizationServiceBox(transcriptionClient)
        transcriptionClient.shouldFailTranscription = true
        let coordinator = IncrementalTranscriptionCoordinator(
            transcriptionID: UUID(),
            meeting: makeMeeting(),
            inputSource: "system+microphone",
            storage: storage,
            transcriptionClientBox: transcriptionClientBox,
            callbacks: .init(
                onProcessedDurationChanged: { _ in }
            ),
            fallbackLogMessage: "Meeting incremental transcription degraded; full-file fallback required"
        )

        try await coordinator.start()
        try await coordinator.append(
            bufferBox: RecordingManager.SendableIncrementalAudioBufferBox(
                buffer: makeBuffer(segments: [.tone(1.0, amplitude: 0.25)])
            )
        )

        do {
            _ = try await coordinator.finish(
                audioURL: URL(fileURLWithPath: "/tmp/meeting-test.wav"),
                diarizationEnabled: true,
                finalDiarizationServiceBox: finalDiarizationServiceBox
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

    func testFinish_WhenNoIncrementalTranscriptIsProduced_MarksFallbackAndThrows() async throws {
        let storage = MockStorageService()
        let transcriptionClient = MockTranscriptionClient()
        let transcriptionClientBox = RecordingManager.UncheckedTranscriptionServiceBox(transcriptionClient)
        let finalDiarizationServiceBox = RecordingManager.UncheckedFinalDiarizationServiceBox(transcriptionClient)
        let coordinator = IncrementalTranscriptionCoordinator(
            transcriptionID: UUID(),
            meeting: makeMeeting(),
            inputSource: "system+microphone",
            storage: storage,
            transcriptionClientBox: transcriptionClientBox,
            callbacks: .init(
                onProcessedDurationChanged: { _ in }
            ),
            fallbackLogMessage: "Meeting incremental transcription degraded; full-file fallback required"
        )

        try await coordinator.start()

        do {
            _ = try await coordinator.finish(
                audioURL: URL(fileURLWithPath: "/tmp/meeting-test.wav"),
                diarizationEnabled: true,
                finalDiarizationServiceBox: finalDiarizationServiceBox
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
        let fallbackError = await coordinator.fallbackError

        XCTAssertTrue(requiresLegacyFallback)
        XCTAssertEqual(fallbackReason, .emptyTranscript)
        XCTAssertNotNil(fallbackError)
        XCTAssertEqual(storage.savedTranscriptions.last?.lifecycleState, .finalizing)
        XCTAssertEqual(transcriptionClient.fileTranscribeCallCount, 0)
        XCTAssertEqual(transcriptionClient.sampleTranscribeCallCount, 0)
    }

    func testFinish_WhenFinalDiarizationFails_MarksFallbackAndThrows() async throws {
        let storage = MockStorageService()
        let transcriptionClient = MockTranscriptionClient()
        let transcriptionClientBox = RecordingManager.UncheckedTranscriptionServiceBox(transcriptionClient)
        let finalDiarizationServiceBox = RecordingManager.UncheckedFinalDiarizationServiceBox(transcriptionClient)
        transcriptionClient.mockText = "meeting partial"
        transcriptionClient.mockSegments = [
            CaptureArtifact.Segment(
                speaker: CaptureArtifact.unknownSpeaker,
                text: "meeting partial",
                startTime: 0,
                endTime: 1.0
            )
        ]
        transcriptionClient.shouldFailDiarization = true

        let coordinator = IncrementalTranscriptionCoordinator(
            transcriptionID: UUID(),
            meeting: makeMeeting(),
            inputSource: "system+microphone",
            storage: storage,
            transcriptionClientBox: transcriptionClientBox,
            callbacks: .init(
                onProcessedDurationChanged: { _ in }
            ),
            fallbackLogMessage: "Meeting incremental transcription degraded; full-file fallback required"
        )

        try await coordinator.start()
        try await coordinator.append(
            bufferBox: RecordingManager.SendableIncrementalAudioBufferBox(
                buffer: makeBuffer(segments: [.tone(1.0, amplitude: 0.25)])
            )
        )

        do {
            _ = try await coordinator.finish(
                audioURL: URL(fileURLWithPath: "/tmp/meeting-test.wav"),
                diarizationEnabled: true,
                finalDiarizationServiceBox: finalDiarizationServiceBox
            )
            XCTFail("Expected finish to throw")
        } catch {}

        let requiresLegacyFallback = await coordinator.requiresLegacyFallback
        let fallbackReason = await coordinator.fallbackReason
        let fallbackError = await coordinator.fallbackError

        XCTAssertTrue(requiresLegacyFallback)
        XCTAssertEqual(fallbackReason, .finalDiarizationFailed)
        XCTAssertNotNil(fallbackError)
        XCTAssertEqual(storage.savedTranscriptions.last?.lifecycleState, .finalizing)
        XCTAssertEqual(transcriptionClient.sampleTranscribeCallCount, 1)
        XCTAssertEqual(transcriptionClient.diarizeCallCount, 1)
    }

    private func makeMeeting() -> CaptureSession {
        CaptureSession(
            app: .unknown,
            capturePurpose: .meeting,
            title: "Meeting Test",
            audioFilePath: "/tmp/meeting-test.wav"
        )
    }

    private func makeBuffer(segments: [CoordinatorSampleSegment], sampleRate: Double = 16000) throws -> AVAudioPCMBuffer {
        let samples = segments.flatMap { segment in
            let sampleCount = Int(segment.duration * sampleRate)
            return (0 ..< sampleCount).map { frameIndex in
                segment.sample(at: frameIndex, sampleRate: sampleRate)
            }
        }

        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let frameCount = AVAudioFrameCount(samples.count)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData else {
            throw NSError(domain: "IncrementalMeetingCoordinatorTests", code: 1)
        }

        for (index, sample) in samples.enumerated() {
            channelData[0][index] = sample
        }

        return buffer
    }
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

private final class ProcessedDurationRecorder: @unchecked Sendable {
    var values: [Double] = []
}

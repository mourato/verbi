import AVFoundation
@testable import VerbiCore
@testable import VerbiCoreAI
@testable import VerbiCoreUI
import XCTest

/// Covers remote incremental dictation (Issue #177): routing, ordered window
/// joins, short-dictation single requests, hidden live preview, short-silence
/// detection, chunk failure fallback, and indicator/status policy constants.
@MainActor
final class RemoteIncrementalDictationTests: XCTestCase {
    func testSupportsIncremental_TrueForRemoteProviders() {
        let client = TranscriptionClient()
        for provider in [TranscriptionProvider.groq, TranscriptionProvider.elevenLabs, TranscriptionProvider.openai] {
            let selection = TranscriptionProviderSelection(provider: provider, selectedModel: provider.defaultModelID)
            XCTAssertTrue(client.supportsIncrementalTranscription(selection: selection), "provider \(provider)")
        }
        let local = TranscriptionProviderSelection(provider: .local, selectedModel: LocalTranscriptionModel.parakeetTdt06BV3.rawValue)
        XCTAssertTrue(client.supportsIncrementalTranscription(selection: local))
    }

    func testBatcher_JoinsWindowsInSequenceOrderNotArrivalOrder() async throws {
        let batcher = IncrementalRemoteWindowBatcher(dispatchThresholdSeconds: 0.5)
        let started = CompletionRecorder()
        let finished = CompletionRecorder()
        let gateSlow = Gate()
        let gateFast = Gate()
        let transcribe: @Sendable ([Float]) async throws -> TranscriptionResponse = { samples in
            if samples.count == 100 {
                await started.record("slow")
                await gateSlow.wait()
                await finished.record("slow")
                return Self.makeResponse(text: "slow text")
            } else {
                await started.record("fast")
                await gateFast.wait()
                await finished.record("fast")
                return Self.makeResponse(text: "fast text")
            }
        }

        await batcher.ingest(samples: [Float](repeating: 0.1, count: 100), startTime: 0, endTime: 0.3, transcribe: transcribe)
        await batcher.ingest(samples: [Float](repeating: 0.1, count: 200), startTime: 0.3, endTime: 0.6, transcribe: transcribe)

        // Wait for both window requests to start, then let the fast window
        // finish first: the join must still follow window order.
        try await Self.waitUntil("both windows start") { await started.order.count == 2 }
        await gateFast.trip()
        try await Self.waitUntil("fast window finishes") { await finished.order == ["fast"] }
        await gateSlow.trip()

        let completed = try await batcher.drainOrdered()
        XCTAssertEqual(completed.map(\.sequence), [0, 1])
        XCTAssertEqual(completed.map(\.response.text), ["slow text", "fast text"])
        let finishedOrder = await finished.order
        XCTAssertEqual(finishedOrder, ["fast", "slow"])
    }

    func testBatcher_ShortSpeechDispatchesNoWindowRequests() async throws {
        let batcher = IncrementalRemoteWindowBatcher()
        let counter = TranscribeCounter()
        let transcribe: @Sendable ([Float]) async throws -> TranscriptionResponse = { _ in
            await counter.increment()
            return Self.makeResponse(text: "unexpected")
        }

        await batcher.ingest(samples: [Float](repeating: 0.1, count: 100), startTime: 0, endTime: 2.0, transcribe: transcribe)

        let didDispatch = await batcher.didDispatchAny
        XCTAssertFalse(didDispatch)
        do {
            _ = try await batcher.drainOrdered()
            XCTFail("Expected RemoteShortDictationSingleRequestError")
        } catch is RemoteShortDictationSingleRequestError {
            // Short dictations stay on one full-file request.
        }
        let shortTranscribeCount = await counter.count
        XCTAssertEqual(shortTranscribeCount, 0)
    }

    func testBatcher_LongSpeechDispatchesEveryWindow() async throws {
        let batcher = IncrementalRemoteWindowBatcher()
        let counter = TranscribeCounter()
        let transcribe: @Sendable ([Float]) async throws -> TranscriptionResponse = { samples in
            await counter.increment()
            return Self.makeResponse(text: "window \(samples.count)")
        }

        await batcher.ingest(samples: [Float](repeating: 0.1, count: 100), startTime: 0, endTime: 3.0, transcribe: transcribe)
        await batcher.ingest(samples: [Float](repeating: 0.1, count: 100), startTime: 3.0, endTime: 6.0, transcribe: transcribe)

        let longDidDispatch = await batcher.didDispatchAny
        XCTAssertTrue(longDidDispatch)
        let completed = try await batcher.drainOrdered()
        XCTAssertEqual(completed.count, 2)
        let longTranscribeCount = await counter.count
        XCTAssertEqual(longTranscribeCount, 2)
    }

    func testCoordinator_RemoteHidesLivePreviewButKeepsFullText() async throws {
        let storage = MockStorageService()
        let transcriptionClient = MockTranscriptionClient()
        transcriptionClient.mockText = "ola mundo"
        let transcriptionClientBox = RecordingManager.UncheckedTranscriptionServiceBox(transcriptionClient)
        let previewRecorder = PreviewRecorder()
        let coordinator = IncrementalTranscriptionCoordinator(
            transcriptionID: UUID(),
            meeting: Self.makeMeeting(),
            inputSource: "microphone",
            storage: storage,
            transcriptionClientBox: transcriptionClientBox,
            callbacks: .init(
                onPreviewTextChanged: { text in previewRecorder.values.append(text) },
                onProcessedDurationChanged: { _ in }
            ),
            fallbackLogMessage: "Dictation incremental transcription degraded; full-file fallback required",
            isRemote: true,
            suppressLivePreview: true,
            remoteDispatchThresholdSeconds: 0.1
        )

        try await coordinator.start()
        let dictationBuffer = try Self.makeBuffer(duration: 1.0, amplitude: 0.25)
        try await coordinator.append(
            bufferBox: RecordingManager.SendableIncrementalAudioBufferBox(buffer: dictationBuffer)
        )

        let result = try await coordinator.finish(
            audioURL: URL(fileURLWithPath: "/tmp/remote-dictation-test.wav"),
            diarizationEnabled: false,
            finalDiarizationServiceBox: nil
        )
        XCTAssertFalse(result.response.text.isEmpty)
        XCTAssertTrue(previewRecorder.values.isEmpty, "Remote dictation must not publish partial preview text")
    }

    func testCoordinator_RemoteWindowFailureMarksFallbackForFullFile() async throws {
        let storage = MockStorageService()
        let transcriptionClient = MockTranscriptionClient()
        transcriptionClient.shouldFailTranscription = true
        let transcriptionClientBox = RecordingManager.UncheckedTranscriptionServiceBox(transcriptionClient)
        let coordinator = IncrementalTranscriptionCoordinator(
            transcriptionID: UUID(),
            meeting: Self.makeMeeting(),
            inputSource: "microphone",
            storage: storage,
            transcriptionClientBox: transcriptionClientBox,
            callbacks: .init(
                onPreviewTextChanged: { _ in },
                onProcessedDurationChanged: { _ in }
            ),
            fallbackLogMessage: "Dictation incremental transcription degraded; full-file fallback required",
            isRemote: true,
            suppressLivePreview: true,
            remoteDispatchThresholdSeconds: 0.1
        )

        try await coordinator.start()
        let failingBuffer = try Self.makeBuffer(duration: 1.0, amplitude: 0.25)
        try await coordinator.append(
            bufferBox: RecordingManager.SendableIncrementalAudioBufferBox(buffer: failingBuffer)
        )

        do {
            _ = try await coordinator.finish(
                audioURL: URL(fileURLWithPath: "/tmp/remote-dictation-test.wav"),
                diarizationEnabled: false,
                finalDiarizationServiceBox: nil
            )
            XCTFail("Expected finish to throw")
        } catch is RemoteShortDictationSingleRequestError {
            XCTFail("A dispatched window failure must fall back, not take the short path")
        } catch {}

        let remoteRequiresFallback = await coordinator.requiresLegacyFallback
        XCTAssertTrue(remoteRequiresFallback)
        let remoteFallbackReason = await coordinator.fallbackReason
        XCTAssertEqual(remoteFallbackReason, .windowTranscriptionFailed)
    }

    func testSilenceMetrics_DistinguishesSilenceFromSpeech() {
        let silent = RemoteWindowAudioSupport.silenceMetrics(samples: [Float](repeating: 0, count: 1600))
        XCTAssertEqual(silent.peak, 0)
        XCTAssertEqual(silent.rms, 0)

        let tone = (0 ..< 1600).map { frame in sin(Float(frame) * 0.1) * 0.25 }
        let speech = RemoteWindowAudioSupport.silenceMetrics(samples: tone)
        XCTAssertGreaterThan(speech.peak, RemoteIncrementalDictationPolicy.silencePeakThreshold)
        XCTAssertGreaterThan(speech.rms, RemoteIncrementalDictationPolicy.silenceRMSThreshold)
    }

    func testRateLimitClassifier_FlagsProviderThrottling() {
        let rateLimited = TranscriptionError.transcriptionFailed("Groq transcription failed with status 429")
        XCTAssertTrue(RemoteWindowAudioSupport.isRateLimited(rateLimited))
        let generic = TranscriptionError.transcriptionFailed("connection reset")
        XCTAssertFalse(RemoteWindowAudioSupport.isRateLimited(generic))
    }

    func testRemotePolicy_PreservesPerceivedSpeedBudgets() {
        XCTAssertEqual(RemoteIncrementalDictationPolicy.shortDictationSingleRequestSeconds, 5.0)
        XCTAssertEqual(RemoteIncrementalDictationPolicy.shortSilenceSkipSeconds, 4.0)
        XCTAssertEqual(RemoteIncrementalDictationPolicy.transcribingStateDelayNanoseconds, 250_000_000)
    }

    // MARK: - Helpers

    private static func waitUntil(
        _ description: String,
        timeoutIterations: Int = 10000,
        condition: () async -> Bool
    ) async throws {
        for _ in 0 ..< timeoutIterations {
            if await condition() {
                return
            }
            await Task.yield()
        }
        throw NSError(
            domain: "RemoteIncrementalDictationTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for \(description)"]
        )
    }

    private nonisolated static func makeResponse(text: String) -> TranscriptionResponse {
        TranscriptionResponse(
            text: text,
            segments: [],
            language: "pt",
            durationSeconds: 1,
            model: "whisper-large-v3-turbo",
            processedAt: Date().ISO8601Format(),
            confidenceScore: nil
        )
    }

    private static func makeMeeting() -> CaptureSession {
        CaptureSession(
            app: .unknown,
            capturePurpose: .dictation,
            title: "Remote Dictation Test",
            audioFilePath: "/tmp/remote-dictation-test.wav"
        )
    }

    private static func makeBuffer(duration: Double, amplitude: Float, sampleRate: Double = 16000) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        let channelData = try XCTUnwrap(buffer.floatChannelData)
        for index in 0 ..< Int(frameCount) {
            let angle = 2 * Double.pi * Double(index) * 220 / sampleRate
            channelData[0][index] = sin(Float(angle)) * amplitude
        }
        return buffer
    }
}

private actor CompletionRecorder {
    var order: [String] = []
    func record(_ value: String) {
        order.append(value)
    }
}

private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func trip() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            // No suspension point precedes this body, so a concurrent trip
            // either ran before (isOpen) or resumes the appended waiter.
            if isOpen {
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }
    }
}

private actor TranscribeCounter {
    var count = 0
    func increment() {
        count += 1
    }
}

private final class PreviewRecorder: @unchecked Sendable {
    var values: [String] = []
}

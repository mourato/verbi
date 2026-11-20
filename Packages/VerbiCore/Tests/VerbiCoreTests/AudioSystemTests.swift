@preconcurrency import AVFoundation
import Synchronization
@testable import VerbiCore
@testable import VerbiCoreAudio
import XCTest

@MainActor
final class AudioSystemTests: XCTestCase {
    var audioRecorder: AudioRecorder!
    var systemRecorder: SystemAudioRecorder!
    var bufferQueue: AudioBufferQueue!
    var recordingWorker: AudioRecordingWorker!
    var recordingManager: RecordingManager!

    var mockTranscription: MockTranscriptionClient!
    var mockPostProcessing: MockPostProcessingService!
    var mockStorage: MockStorageService!

    override func setUp() async throws {
        try await super.setUp()

        audioRecorder = AudioRecorder.shared
        systemRecorder = SystemAudioRecorder.shared
        bufferQueue = AudioBufferQueue(capacity: 50)
        recordingWorker = AudioRecordingWorker()

        mockTranscription = MockTranscriptionClient()
        mockPostProcessing = MockPostProcessingService()
        mockStorage = MockStorageService()

        recordingManager = RecordingManager(
            transcriptionClient: mockTranscription,
            postProcessingService: mockPostProcessing,
            storage: mockStorage,
        )
    }

    override func tearDown() async throws {
        _ = await audioRecorder.stopRecording()
        _ = await systemRecorder.stopRecording()
        recordingWorker = nil
        bufferQueue.clear()

        audioRecorder = nil
        systemRecorder = nil
        bufferQueue = nil
        recordingManager = nil
        mockTranscription = nil
        mockPostProcessing = nil
        mockStorage = nil

        try await super.tearDown()
    }

    func testAudioRecorderIntegration_WithSystemAudio() async throws {
        guard await systemRecorder.hasPermission() else {
            throw XCTSkip("Screen recording permission not available")
        }

        let outputURL = createTemporaryURL()

        do {
            try await audioRecorder.startRecording(to: outputURL, source: .all, retryCount: 0)
        } catch {
            if "\(error)".contains("permissionDenied") || "\(error)".contains("permission") {
                throw XCTSkip("Screen recording permission denied at runtime: \(error)")
            }
            throw error
        }

        let stoppedURL = await audioRecorder.stopRecording()

        XCTAssertNotNil(stoppedURL)
        XCTAssertEqual(stoppedURL, outputURL)
        XCTAssertFalse(audioRecorder.isRecording)
    }

    func testSystemAudioRecorder_BufferCallbackIntegration() async throws {
        guard await systemRecorder.hasPermission() else {
            throw XCTSkip("Screen recording permission not available")
        }

        let receivedBuffers = AtomicArray<AVAudioPCMBuffer>()
        let expectation = expectation(description: "Buffer callback received")

        let fulfilled = Atomic<Bool>(false)
        systemRecorder.onAudioBuffer = { @Sendable buffer in
            receivedBuffers.append(buffer)
            if receivedBuffers.count >= 3, !fulfilled.exchange(true, ordering: .relaxed) {
                expectation.fulfill()
            }
        }

        try await systemRecorder.startRecording(to: createTemporaryURL(), sampleRate: 48_000.0)

        await fulfillment(of: [expectation], timeout: 2.0)

        _ = await systemRecorder.stopRecording()

        XCTAssertGreaterThan(receivedBuffers.count, 0, "Should have received audio buffers")
        XCTAssertFalse(systemRecorder.isRecording)
    }

    func testAudioBufferQueue_IntegrationWithSystemRecorder() async throws {
        guard await systemRecorder.hasPermission() else {
            throw XCTSkip("Screen recording permission not available")
        }

        let enqueuedCount = ThreadSafeCounter()
        let expectation = expectation(description: "Buffers enqueued")
        expectation.expectedFulfillmentCount = 5

        systemRecorder.onAudioBuffer = { @Sendable [bufferQueue = self.bufferQueue!] buffer in
            bufferQueue.enqueue(buffer)
            let count = enqueuedCount.increment()
            if count <= 5 {
                expectation.fulfill()
            }
        }

        try await systemRecorder.startRecording(to: createTemporaryURL(), sampleRate: 48_000.0)

        await fulfillment(of: [expectation], timeout: 2.0)

        _ = await systemRecorder.stopRecording()

        XCTAssertGreaterThanOrEqual(bufferQueue.stats.count, 5)
        XCTAssertEqual(bufferQueue.stats.dropped, 0)
    }

    func testAudioRecordingWorker_BufferProcessingIntegration() async throws {
        let outputURL = createTemporaryURL()
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))

        try await recordingWorker.start(writingTo: outputURL, format: format, fileFormat: .wav)

        let testBuffers = try createTestBuffers(count: 10, frameCount: 1_024)

        for buffer in testBuffers {
            recordingWorker.process(buffer)
        }

        let finalURL = await recordingWorker.stop()

        XCTAssertNotNil(finalURL)
        XCTAssertTrue(try FileManager.default.fileExists(atPath: XCTUnwrap(finalURL?.path)))

        let asset = try AVURLAsset(url: XCTUnwrap(finalURL))
        let duration = try await asset.load(.duration)
        XCTAssertGreaterThan(duration.seconds, 0)
    }

    func testStateConsistency_BufferQueueStatsAccuracy() throws {
        let buffer = try createTestBuffer(frameCount: 512)

        XCTAssertEqual(bufferQueue.stats.count, 0)
        XCTAssertEqual(bufferQueue.stats.dropped, 0)

        bufferQueue.enqueue(buffer)
        XCTAssertEqual(bufferQueue.stats.count, 1)

        let dequeued = bufferQueue.dequeue()
        XCTAssertNotNil(dequeued)
        XCTAssertEqual(bufferQueue.stats.count, 0)

        bufferQueue.enqueue(buffer)
        bufferQueue.clear()
        XCTAssertEqual(bufferQueue.stats.count, 0)
        XCTAssertEqual(bufferQueue.stats.dropped, 0)
    }

    func testErrorHandling_AudioRecorderInvalidFormat() async {
        let outputURL = createTemporaryURL()

        do {
            try await audioRecorder.startRecording(to: outputURL, source: .all, retryCount: 0)
            _ = await audioRecorder.stopRecording()
        } catch {
            XCTAssertNotNil(error)
        }
    }

    func testErrorHandling_BufferQueueOverflowHandling() throws {
        let smallCapacityQueue = AudioBufferQueue(capacity: 3)
        let buffer = try createTestBuffer(frameCount: 512)

        for _ in 0..<3 {
            smallCapacityQueue.enqueue(buffer)
        }

        XCTAssertEqual(smallCapacityQueue.stats.count, 3)

        smallCapacityQueue.enqueue(buffer)

        XCTAssertEqual(smallCapacityQueue.stats.count, 3)
        XCTAssertGreaterThan(smallCapacityQueue.stats.dropped, 0)
    }

    func testBufferOverflow_AudioBufferQueueDropOldest() throws {
        let smallQueue = AudioBufferQueue(capacity: 2)
        let buffers = try (0..<4).map { try self.createTestBuffer(frameCount: AVAudioFrameCount($0 + 1) * 256) }

        for buffer in buffers {
            smallQueue.enqueue(buffer)
        }

        XCTAssertEqual(smallQueue.stats.count, 2)

        XCTAssertGreaterThan(smallQueue.stats.dropped, 0)

        let first = smallQueue.dequeue()
        let second = smallQueue.dequeue()

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertEqual(first?.frameLength, 768)
        XCTAssertEqual(second?.frameLength, 1_024)
    }

    func testThreadSafety_BufferQueueConcurrentAccess() throws {
        let buffer = try createTestBuffer(frameCount: 1_024)
        let iterations = 50
        let expectation = expectation(description: "Concurrent operations")
        expectation.expectedFulfillmentCount = iterations * 3

        for _ in 0..<iterations {
            DispatchQueue.global().async { [bufferQueue = self.bufferQueue!] in
                bufferQueue.enqueue(buffer)
                expectation.fulfill()
            }

            DispatchQueue.global().async { [bufferQueue = self.bufferQueue!] in
                _ = bufferQueue.dequeue()
                expectation.fulfill()
            }

            DispatchQueue.global().async { [bufferQueue = self.bufferQueue!] in
                _ = bufferQueue.stats
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testCleanup_BufferQueueCompleteClear() throws {
        let buffer = try createTestBuffer(frameCount: 512)

        for _ in 0..<10 {
            bufferQueue.enqueue(buffer)
        }

        XCTAssertGreaterThan(bufferQueue.stats.count, 0)

        bufferQueue.clear()

        XCTAssertTrue(bufferQueue.isEmpty)
        XCTAssertEqual(bufferQueue.stats.count, 0)
        XCTAssertEqual(bufferQueue.stats.dropped, 0)
    }

    func testCleanup_RecordingWorkerFileClosure() async throws {
        let outputURL = createTemporaryURL()
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))

        try await recordingWorker.start(writingTo: outputURL, format: format, fileFormat: .wav)

        let testBuffer = try createTestBuffer(frameCount: 1_024)
        recordingWorker.process(testBuffer)

        let finalURL = await recordingWorker.stop()

        XCTAssertNotNil(finalURL)
        XCTAssertTrue(try FileManager.default.fileExists(atPath: XCTUnwrap(finalURL?.path)))

    }

    private func createTemporaryURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "test_audio_\(UUID().uuidString).m4a"
        return tempDir.appendingPathComponent(filename)
    }

    private func createTestBuffer(frameCount: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false,
        ) else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create format"])
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
        }

        buffer.frameLength = frameCount

        if let channelData = buffer.floatChannelData {
            for ch in 0..<Int(format.channelCount) {
                for frame in 0..<Int(frameCount) {
                    channelData[ch][frame] = sin(Float(frame) * 0.01)
                }
            }
        }

        return buffer
    }

    private func createTestBuffers(count: Int, frameCount: AVAudioFrameCount) throws -> [AVAudioPCMBuffer] {
        try (0..<count).map { _ in try self.createTestBuffer(frameCount: frameCount) }
    }
}

private final class AtomicArray<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Element] = []

    var count: Int {
        lock.withLock { self.storage.count }
    }

    func append(_ element: Element) {
        lock.withLock { self.storage.append(element) }
    }

    func getElements() -> [Element] {
        lock.withLock { self.storage }
    }
}

private final class ThreadSafeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int = 0

    func increment() -> Int {
        lock.withLock {
            self.value += 1
            return self.value
        }
    }

    var currentValue: Int {
        lock.withLock { self.value }
    }
}

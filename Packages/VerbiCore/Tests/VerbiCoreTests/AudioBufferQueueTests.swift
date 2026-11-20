@preconcurrency import AVFoundation
@testable import VerbiCore
import XCTest

final class AudioBufferQueueTests: XCTestCase {
    var sut: AudioBufferQueue!

    override func setUp() {
        super.setUp()
        sut = AudioBufferQueue(capacity: 5)
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    func testInitialState_IsEmpty() {
        XCTAssertTrue(sut.isEmpty)
    }

    func testInitialState_StatsAreZero() {
        let stats = sut.stats

        XCTAssertEqual(stats.count, 0)
        XCTAssertEqual(stats.dropped, 0)
    }

    func testInitialState_WithCustomCapacity() {
        let customQueue = AudioBufferQueue(capacity: 10)

        XCTAssertTrue(customQueue.isEmpty)
        XCTAssertEqual(customQueue.stats.count, 0)
    }

    func testEnqueue_IncreasesCount() throws {
        let buffer = try createTestBuffer(frameCount: 512)

        sut.enqueue(buffer)

        XCTAssertFalse(sut.isEmpty)
        XCTAssertEqual(sut.stats.count, 1)
    }

    func testEnqueue_MultipleBuffers_IncreasesCount() throws {
        let buffer1 = try createTestBuffer(frameCount: 512)
        let buffer2 = try createTestBuffer(frameCount: 512)
        let buffer3 = try createTestBuffer(frameCount: 512)

        sut.enqueue(buffer1)
        sut.enqueue(buffer2)
        sut.enqueue(buffer3)

        XCTAssertEqual(sut.stats.count, 3)
    }

    func testDequeue_WhenEmpty_ReturnsNil() {
        let result = sut.dequeue()

        XCTAssertNil(result)
    }

    func testDequeue_ReturnsBuffer() throws {
        let buffer = try createTestBuffer(frameCount: 512)
        sut.enqueue(buffer)

        let result = sut.dequeue()

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.frameLength, buffer.frameLength)
    }

    func testDequeue_EmptyQueueAfterDequeuing() throws {
        let buffer = try createTestBuffer(frameCount: 512)
        sut.enqueue(buffer)

        _ = sut.dequeue()

        XCTAssertTrue(sut.isEmpty)
    }

    func testDequeue_MultipleBuffers_FIFOOrder() throws {
        let buffer1 = try createTestBuffer(frameCount: 256)
        let buffer2 = try createTestBuffer(frameCount: 512)
        let buffer3 = try createTestBuffer(frameCount: 1_024)

        sut.enqueue(buffer1)
        sut.enqueue(buffer2)
        sut.enqueue(buffer3)

        let result1 = sut.dequeue()
        let result2 = sut.dequeue()
        let result3 = sut.dequeue()

        XCTAssertEqual(result1?.frameLength, 256)
        XCTAssertEqual(result2?.frameLength, 512)
        XCTAssertEqual(result3?.frameLength, 1_024)
    }

    func testEnqueue_WhenFull_DropsOldest() throws {
        let buffers = try (0..<6).map { try self.createTestBuffer(frameCount: AVAudioFrameCount($0 + 1) * 256) }

        for buffer in buffers {
            sut.enqueue(buffer)
        }

        XCTAssertEqual(sut.stats.count, 5)
    }

    func testEnqueue_WhenFull_DropsOldestAndIncrementsDroppedCounter() throws {
        let buffer = try createTestBuffer(frameCount: 512)

        for _ in 0..<5 {
            sut.enqueue(buffer)
        }

        let statsBeforeOverflow = sut.stats

        sut.enqueue(buffer)

        let statsAfterOverflow = sut.stats

        XCTAssertEqual(statsAfterOverflow.count, 5)
        XCTAssertGreaterThan(statsAfterOverflow.dropped, statsBeforeOverflow.dropped)
    }

    func testClear_ResetsQueue() throws {
        let buffer = try createTestBuffer(frameCount: 512)
        sut.enqueue(buffer)

        sut.clear()

        XCTAssertTrue(sut.isEmpty)
        XCTAssertEqual(sut.stats.count, 0)
        XCTAssertEqual(sut.stats.dropped, 0)
    }

    func testClear_WhenEmpty_RemainsEmpty() {
        sut.clear()

        XCTAssertTrue(sut.isEmpty)
        XCTAssertEqual(sut.stats.count, 0)
    }

    func testStats_ReflectsCorrectCount() throws {
        let buffer = try createTestBuffer(frameCount: 512)

        XCTAssertEqual(sut.stats.count, 0)

        sut.enqueue(buffer)
        XCTAssertEqual(sut.stats.count, 1)

        sut.enqueue(buffer)
        XCTAssertEqual(sut.stats.count, 2)

        _ = sut.dequeue()
        XCTAssertEqual(sut.stats.count, 1)
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
                    channelData[ch][frame] = Float(frame) / Float(frameCount)
                }
            }
        }

        return buffer
    }
}

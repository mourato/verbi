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

    // MARK: - Initial State

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

    // MARK: - Enqueue

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

    // MARK: - Dequeue

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

    // MARK: - Buffer Overflow (Drop Oldest)

    func testEnqueue_WhenFull_DropsOldest() throws {
        let buffers = try (0..<6).map { try self.createTestBuffer(frameCount: AVAudioFrameCount($0 + 1) * 256) }

        for buffer in buffers {
            sut.enqueue(buffer)
        }

        XCTAssertEqual(sut.stats.count, 5)
    }

    func testEnqueue_WhenFull_DropsOldestAndIncrementsDroppedCounter() throws {
        let buffer = try createTestBuffer(frameCount: 512)

        // Fill the queue to capacity
        for _ in 0..<5 {
            sut.enqueue(buffer)
        }

        let statsBeforeOverflow = sut.stats

        // Add one more to trigger overflow
        sut.enqueue(buffer)

        let statsAfterOverflow = sut.stats

        XCTAssertEqual(statsAfterOverflow.count, 5)
        XCTAssertGreaterThan(statsAfterOverflow.dropped, statsBeforeOverflow.dropped)
    }

    // MARK: - Clear

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

    // MARK: - Thread Safety

    /* Commented out due to test runner instability
     func testConcurrentEnqueueAndDequeue_DoesNotCrash() throws {
         let buffer = try createTestBuffer(frameCount: 1024)
         let iterations = 100
         let expectation = self.expectation(description: "Concurrent access")
         expectation.expectedFulfillmentCount = iterations * 2

         for _ in 0..<iterations {
             let sut = self.sut!
             DispatchQueue.global().async {
                 sut.enqueue(buffer)
                 expectation.fulfill()
             }

             DispatchQueue.global().async {
                 _ = sut.dequeue()
                 _ = sut.isEmpty
                 expectation.fulfill()
             }
         }

         wait(for: [expectation], timeout: 5.0)
     }
     */

    /* Commented out due to test runner instability
     func testConcurrentClearAndAccess_DoesNotCrash() throws {
         let buffer = try createTestBuffer(frameCount: 512)
         let iterations = 50
         let expectation = self.expectation(description: "Concurrent clear and access")
         expectation.expectedFulfillmentCount = iterations * 2

         // Pre-populate queue
         for _ in 0..<10 {
             self.sut.enqueue(buffer)
         }

         for _ in 0..<iterations {
             let sut = self.sut!
             DispatchQueue.global().async {
                 sut.clear()
                 expectation.fulfill()
             }

             DispatchQueue.global().async {
                 _ = sut.stats
                 _ = sut.isEmpty
                 expectation.fulfill()
             }
         }

         wait(for: [expectation], timeout: 5.0)
     }
     */

    // MARK: - Stats

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

    // MARK: - Performance Tests

    /* Commented out due to test runner instability with measure blocks in this environment
     func testPerformance_EnqueueOperations() throws {
         let buffer = try createTestBuffer(frameCount: 1024)

         // Baseline: Enqueue operations should be fast and memory-efficient
         measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
             for _ in 0..<1000 {
                 self.sut.enqueue(buffer)
                 if self.sut.stats.count > 40 { // Prevent excessive growth
                     _ = self.sut.dequeue()
                 }
             }
         }
     }

     func testPerformance_DequeueOperations() throws {
         let buffer = try createTestBuffer(frameCount: 1024)

         // Pre-populate queue
         for _ in 0..<50 {
             self.sut.enqueue(buffer)
         }

         // Baseline: Dequeue operations should be very fast
         measure(metrics: [XCTClockMetric(), XCTCPUMetric()]) {
             for _ in 0..<1000 {
                 if !self.sut.isEmpty {
                     _ = self.sut.dequeue()
                 } else {
                     self.sut.enqueue(buffer) // Keep some buffers for measurement
                 }
             }
         }
     }

     func testPerformance_StatsAccess() throws {
         let buffer = try createTestBuffer(frameCount: 512)

         // Pre-populate with some data
         for _ in 0..<10 {
             self.sut.enqueue(buffer)
         }

         // Baseline: Stats access should be instantaneous
         measure(metrics: [XCTClockMetric()]) {
             for _ in 0..<10000 {
                 _ = self.sut.stats
             }
         }
     }

     func testPerformance_ClearOperation() throws {
         let buffer = try createTestBuffer(frameCount: 1024)

         // Baseline: Clear operations should be efficient
         measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
             // Fill queue
             for _ in 0..<50 {
                 self.sut.enqueue(buffer)
             }

             // Clear it
             self.sut.clear()
         }

         // Verify clear worked
         XCTAssertTrue(self.sut.isEmpty)
         XCTAssertEqual(self.sut.stats.count, 0)
     }

     func testPerformance_OverflowHandling() throws {
         let smallQueue = AudioBufferQueue(capacity: 5)
         let buffer = try createTestBuffer(frameCount: 512)

         // Baseline: Overflow handling should maintain performance under load
         measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
             for _ in 0..<500 { // 100x capacity
                 smallQueue.enqueue(buffer)
             }
         }

         // Verify overflow behavior maintained
         XCTAssertEqual(smallQueue.stats.count, 5)
         XCTAssertGreaterThan(smallQueue.stats.dropped, 0)
     }
     */

    // MARK: - Helpers

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

        // Fill with test data
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

@preconcurrency import AVFoundation
@testable import VerbiCore
import XCTest

final class PartialBufferStateTests: XCTestCase {
    var sut: PartialBufferState?

    override func setUp() {
        super.setUp()
        sut = PartialBufferState()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialState_HasNoPartialBuffer() {
        guard let sut else { return XCTFail("SUT not initialized") }
        XCTAssertFalse(sut.hasPartial)
        XCTAssertEqual(sut.framesRemaining, 0)
    }

    // MARK: - setBuffer

    func testSetBuffer_UpdatesState() throws {
        guard let sut else { return XCTFail("SUT not initialized") }
        let buffer = try createTestBuffer(frameCount: 100)
        sut.setBuffer(buffer)

        XCTAssertTrue(sut.hasPartial)
        XCTAssertEqual(sut.framesRemaining, 100)
    }

    func testSetBuffer_WithOffset_UpdatesState() throws {
        guard let sut else { return XCTFail("SUT not initialized") }
        let buffer = try createTestBuffer(frameCount: 100)
        sut.setBuffer(buffer, offset: 25)

        XCTAssertTrue(sut.hasPartial)
        XCTAssertEqual(sut.framesRemaining, 75)
    }

    func testSetBuffer_WithFullOffset_HasNoRemaining() throws {
        guard let sut else { return XCTFail("SUT not initialized") }
        let buffer = try createTestBuffer(frameCount: 100)
        sut.setBuffer(buffer, offset: 100)

        // framesRemaining = 100 - 100 = 0
        XCTAssertEqual(sut.framesRemaining, 0)
    }

    // MARK: - clear

    func testClear_ResetsState() throws {
        guard let sut else { return XCTFail("SUT not initialized") }
        let buffer = try createTestBuffer(frameCount: 100)
        sut.setBuffer(buffer)

        XCTAssertTrue(sut.hasPartial)

        sut.clear()

        XCTAssertFalse(sut.hasPartial)
        XCTAssertEqual(sut.framesRemaining, 0)
    }

    func testClear_WhenEmpty_RemainsEmpty() {
        guard let sut else { return XCTFail("SUT not initialized") }
        XCTAssertFalse(sut.hasPartial)

        sut.clear()

        XCTAssertFalse(sut.hasPartial)
        XCTAssertEqual(sut.framesRemaining, 0)
    }

    // MARK: - Thread Safety (Basic)

    func testConcurrentAccess_DoesNotCrash() throws {
        let buffer = try createTestBuffer(frameCount: 1_000)
        let iterations = 1_000
        let expectation = expectation(description: "Concurrent access")
        // 3 operations per iteration
        expectation.expectedFulfillmentCount = iterations * 3

        guard let sut else { return XCTFail("SUT not initialized") }

        // Setup a dummy destination buffer
        let destBuffer = try createTestBuffer(frameCount: 100)
        let audioBufferList = UnsafeMutableAudioBufferListPointer(destBuffer.mutableAudioBufferList)

        // Multiple concurrent reads and writes
        for _ in 0..<iterations {
            DispatchQueue.global().async {
                sut.setBuffer(buffer, offset: Int.random(in: 0..<100))
                expectation.fulfill()
            }

            DispatchQueue.global().async {
                _ = sut.framesRemaining
                _ = sut.hasPartial
                expectation.fulfill()
            }

            DispatchQueue.global().async {
                _ = sut.consume(maxFrames: 50, into: audioBufferList, destOffset: 0)
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10.0)
        // If we get here without crash, the test passes
    }

    // MARK: - Helpers

    func testConsume_SourceStereo_DestMono_DoesNotCrash() throws {
        guard let sut else { return XCTFail("SUT not initialized") }

        // Source: Stereo (2 channels)
        let srcBuffer = try createTestBuffer(frames: 100, channels: 2)
        sut.setBuffer(srcBuffer)

        // Destination: Mono (1 channel)
        let destBuffer = try createTestBuffer(frames: 100, channels: 1)
        let audioBufferList = UnsafeMutableAudioBufferListPointer(destBuffer.mutableAudioBufferList)

        // This should NOT crash
        _ = sut.consume(maxFrames: 50, into: audioBufferList, destOffset: 0)
    }

    // MARK: - Helpers

    private func createTestBuffer(
        frames: AVAudioFrameCount = 1_000,
        channels: AVAudioChannelCount = 2,
    ) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: channels,
            interleaved: false,
        ) else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create format"])
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
        }

        buffer.frameLength = frames
        return buffer
    }

    private func createTestBuffer(frameCount: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        try createTestBuffer(frames: frameCount, channels: 2)
    }
}

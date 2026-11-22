@preconcurrency import AVFoundation
@testable import VerbiCoreAudio
import XCTest

final class SystemAudioRecorderTests: XCTestCase {
    func testRecoveryDelayDoublesEachAttempt() {
        XCTAssertEqual(SystemAudioRecoveryPolicy.delay(forAttempt: 1), .milliseconds(250))
        XCTAssertEqual(SystemAudioRecoveryPolicy.delay(forAttempt: 2), .milliseconds(500))
        XCTAssertEqual(SystemAudioRecoveryPolicy.delay(forAttempt: 3), .milliseconds(1000))
    }

    func testRecoveryDelayClampsNonPositiveAttempt() {
        XCTAssertEqual(SystemAudioRecoveryPolicy.delay(forAttempt: 0), .milliseconds(250))
    }

    func testClassifyNoBuffersIsFailure() {
        XCTAssertEqual(
            SystemAudioRecoveryPolicy.classify(buffersReceived: false, signalReceived: false),
            .noBuffers
        )
    }

    func testClassifySilentBuffersAreNotFailure() {
        XCTAssertEqual(
            SystemAudioRecoveryPolicy.classify(buffersReceived: true, signalReceived: false),
            .silent
        )
    }

    func testClassifyAudibleBuffersAreNotFailure() {
        XCTAssertEqual(
            SystemAudioRecoveryPolicy.classify(buffersReceived: true, signalReceived: true),
            .audible
        )
    }

    func testSilentBufferContainsNoSignal() throws {
        XCTAssertFalse(try SystemAudioRecoveryPolicy.bufferContainsSignal(makeBuffer(fill: 0)))
    }

    func testAudibleBufferContainsSignal() throws {
        XCTAssertTrue(try SystemAudioRecoveryPolicy.bufferContainsSignal(makeBuffer(fill: 0.5)))
    }

    func testEmptyBufferContainsNoSignal() throws {
        let buffer = try makeBuffer(fill: 0)
        buffer.frameLength = 0
        XCTAssertFalse(SystemAudioRecoveryPolicy.bufferContainsSignal(buffer))
    }

    private func makeBuffer(fill value: Float) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: 2,
            interleaved: false
        ))
        let frameCount: AVAudioFrameCount = 1024
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        let channelData = try XCTUnwrap(buffer.floatChannelData)
        for channel in 0 ..< Int(format.channelCount) {
            channelData[channel].update(repeating: value, count: Int(frameCount))
        }
        return buffer
    }
}

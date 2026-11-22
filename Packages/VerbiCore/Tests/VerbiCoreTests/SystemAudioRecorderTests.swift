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
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: 2,
            interleaved: false
        ) else {
            throw NSError(domain: "SystemAudioRecorderTests", code: 1)
        }
        let frameCount: AVAudioFrameCount = 1024
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "SystemAudioRecorderTests", code: 2)
        }
        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData else {
            throw NSError(domain: "SystemAudioRecorderTests", code: 3)
        }
        for channel in 0 ..< Int(format.channelCount) {
            for frame in 0 ..< Int(frameCount) {
                channelData[channel][frame] = value
            }
        }
        return buffer
    }
}

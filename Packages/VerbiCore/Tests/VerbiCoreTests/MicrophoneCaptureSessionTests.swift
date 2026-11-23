import AVFoundation
@testable import VerbiCoreAudio
import XCTest

final class MicrophoneCaptureSessionTests: XCTestCase {
    func testAppendEmitsFullStereoChunksWithMonoSamplesInBothChannels() throws {
        let emitted = EmittedBuffers()
        let capture = try MicrophoneCaptureSession { emitted.append($0) }
        let input = try makeMonoBuffer(frameCount: 3000)

        capture.append(input)

        let chunks = emitted.all
        XCTAssertEqual(chunks.count, 1)
        let chunk = try XCTUnwrap(chunks.first)
        XCTAssertEqual(chunk.frameLength, MicrophoneCaptureSession.chunkFrameCount)
        XCTAssertEqual(chunk.format.channelCount, 2)
        let channels = try XCTUnwrap(chunk.floatChannelData)
        for frame in [0, 1000, 2047] {
            XCTAssertEqual(channels[0][frame], Float(frame))
            XCTAssertEqual(channels[1][frame], Float(frame))
        }
    }

    func testStopFlushesPartialChunk() throws {
        let emitted = EmittedBuffers()
        let capture = try MicrophoneCaptureSession { emitted.append($0) }

        try capture.append(makeMonoBuffer(frameCount: 3000))
        capture.stop()

        XCTAssertEqual(emitted.all.map(\.frameLength), [2048, 952])
        let tail = try XCTUnwrap(emitted.all.last?.floatChannelData)
        XCTAssertEqual(tail[1][0], 2048)
    }

    private func makeMonoBuffer(frameCount: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: MicrophoneCaptureSession.sampleRate,
            channels: 1,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for frame in 0 ..< Int(frameCount) {
            samples[frame] = Float(frame)
        }
        return buffer
    }
}

private final class EmittedBuffers: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers: [AVAudioPCMBuffer] = []

    var all: [AVAudioPCMBuffer] {
        lock.withLock { buffers }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { buffers.append(buffer) }
    }
}

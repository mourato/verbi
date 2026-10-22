import AVFoundation
@testable import VerbiCoreAudio
import XCTest

final class VoiceActivityWindowAssemblerTests: XCTestCase {
    func testAppendAndFinish_EmitsWindowWithPrerollAndTail() async throws {
        let assembler = RealtimeVoiceActivityWindowAssembler()
        let samples = makeSamples(segments: [
            .silence(0.30),
            .tone(0.30, amplitude: 0.3),
            .silence(0.60),
        ])
        let buffer = try makeBuffer(samples: samples)

        let windowsDuringAppend = try await assembler.append(buffer: buffer)
        let windows = try await windowsDuringAppend + (assembler.finish())
        XCTAssertEqual(windows.count, 1)

        let window = try XCTUnwrap(windows.first)
        XCTAssertEqual(window.startTime, 0.27, accuracy: 0.05)
        XCTAssertEqual(window.endTime, 0.84, accuracy: 0.08)
        XCTAssertGreaterThan(window.samples.count, Int(0.30 * 16_000))
    }

    func testAppend_LongSpeechCommitsWindowBeforeFinish() async throws {
        let assembler = RealtimeVoiceActivityWindowAssembler()
        let samples = makeSamples(segments: [
            .tone(13.0, amplitude: 0.25),
        ])
        let buffer = try makeBuffer(samples: samples)

        let windowsDuringAppend = try await assembler.append(buffer: buffer)
        XCTAssertEqual(windowsDuringAppend.count, 1)
        XCTAssertGreaterThan(windowsDuringAppend[0].endTime - windowsDuringAppend[0].startTime, 11.5)

        let finalWindows = try await assembler.finish()
        XCTAssertEqual(finalWindows.count, 1)
        XCTAssertGreaterThan(finalWindows[0].endTime - finalWindows[0].startTime, 0.5)
    }

    private func makeBuffer(samples: [Float], sampleRate: Double = 16_000) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let frameCount = AVAudioFrameCount(samples.count)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData else {
            throw NSError(domain: "VoiceActivityWindowAssemblerTests", code: 1)
        }
        for (index, sample) in samples.enumerated() {
            channelData[0][index] = sample
        }
        return buffer
    }

    private func makeSamples(segments: [SampleSegment], sampleRate: Double = 16_000) -> [Float] {
        segments.flatMap { segment in
            let sampleCount = Int(segment.duration * sampleRate)
            return (0..<sampleCount).map { frameIndex in
                segment.sample(at: frameIndex, sampleRate: sampleRate)
            }
        }
    }
}

private struct SampleSegment {
    let duration: Double
    let amplitude: Float

    static func silence(_ duration: Double) -> SampleSegment {
        SampleSegment(duration: duration, amplitude: 0)
    }

    static func tone(_ duration: Double, amplitude: Float) -> SampleSegment {
        SampleSegment(duration: duration, amplitude: amplitude)
    }

    func sample(at frameIndex: Int, sampleRate: Double) -> Float {
        guard amplitude > 0 else { return 0 }
        let angle = 2 * Double.pi * Double(frameIndex) * 220 / sampleRate
        return sin(Float(angle)) * amplitude
    }
}

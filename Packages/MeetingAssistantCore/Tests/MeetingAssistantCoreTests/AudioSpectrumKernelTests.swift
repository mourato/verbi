import AVFoundation
@testable import MeetingAssistantCoreAudio
import XCTest

final class AudioSpectrumKernelTests: XCTestCase {
    private let kernel = SwiftSpectrumKernel.shared

    func testBandCount_IsTwentyOne() {
        XCTAssertEqual(SwiftSpectrumKernel.bandCount, 21)
    }

    func testLevels_ForSilence_ReturnsZeros() {
        let levels = SwiftSpectrumKernel.levels(
            forMonoSamples: [Float](repeating: 0, count: 512)
        )

        XCTAssertEqual(levels.count, SwiftSpectrumKernel.bandCount)
        XCTAssertTrue(levels.allSatisfy { $0 == 0 })
    }

    func testLevels_StaysWithinNormalizedBounds() {
        var samples = [Float](repeating: 0, count: 512)
        for index in samples.indices {
            samples[index] = 0.5 * sin(2 * .pi * Float(440) * Float(index) / 48_000)
        }

        let levels = SwiftSpectrumKernel.levels(forMonoSamples: samples)

        XCTAssertEqual(levels.count, SwiftSpectrumKernel.bandCount)
        XCTAssertTrue(levels.allSatisfy { $0 >= 0 && $0 <= 1 })
        XCTAssertGreaterThan(levels.max() ?? 0, 0.3)
    }

    func testLevels_PeaksNearToneFrequency() {
        var samples = [Float](repeating: 0, count: 1536)
        for index in samples.indices {
            samples[index] = 0.5 * sin(2 * .pi * Float(1000) * Float(index) / 48_000)
        }

        let levels = SwiftSpectrumKernel.levels(forMonoSamples: samples, sampleRate: 48_000)
        let peak = levels.enumerated().max(by: { $0.element < $1.element })?.offset

        // Log edges 32Hz-5kHz over 21 bands put 1kHz in band 14 at any capture rate.
        XCTAssertNotNil(peak)
        XCTAssertTrue((13 ... 15).contains(peak ?? -1), "peak band \(peak ?? -1) outside 13...15")
    }

    func testSampleCount_KeepsThirtyTwoMillisecondWindow() {
        XCTAssertEqual(SwiftSpectrumKernel.sampleCount(forSampleRate: 16000), 512)
        XCTAssertEqual(SwiftSpectrumKernel.sampleCount(forSampleRate: 44100), 1536)
        XCTAssertEqual(SwiftSpectrumKernel.sampleCount(forSampleRate: 48000), 1536)
    }

    func testLevels_IsDeterministic() {
        var samples = [Float](repeating: 0, count: 512)
        for index in samples.indices {
            samples[index] = 0.3 * sin(2 * .pi * Float(220) * Float(index) / 48_000)
        }

        XCTAssertEqual(
            SwiftSpectrumKernel.levels(forMonoSamples: samples),
            SwiftSpectrumKernel.levels(forMonoSamples: samples)
        )
    }

    func testLevels_WithNoSamples_ReturnsZeros() {
        XCTAssertEqual(
            SwiftSpectrumKernel.levels(forMonoSamples: []),
            [Float](repeating: 0, count: SwiftSpectrumKernel.bandCount)
        )
    }

    func testLevelsForBuffer_WithTone_ReturnsBands() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        buffer.frameLength = 512
        guard let channel = buffer.floatChannelData else {
            return XCTFail("Expected float channel data")
        }
        for frame in 0 ..< 512 {
            channel[0][frame] = 0.5 * sin(2 * .pi * Float(440) * Float(frame) / 48_000)
        }

        let levels = kernel.levels(for: buffer)

        XCTAssertEqual(levels.count, SwiftSpectrumKernel.bandCount)
        XCTAssertGreaterThan(levels.max() ?? 0, 0.3)
    }

    func testLevelsForBuffer_WithEmptyBuffer_ReturnsEmpty() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        buffer.frameLength = 0

        XCTAssertEqual(kernel.levels(for: buffer), [])
    }
}

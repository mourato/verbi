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
            forMonoSamples: [Float](repeating: 0, count: 512),
            sampleRate: 48_000
        )

        XCTAssertEqual(levels.count, SwiftSpectrumKernel.bandCount)
        XCTAssertTrue(levels.allSatisfy { $0 == 0 })
    }

    func testLevels_StaysWithinNormalizedBounds() {
        var samples = [Float](repeating: 0, count: 512)
        for index in samples.indices {
            samples[index] = 0.5 * sin(2 * .pi * Float(440) * Float(index) / 48_000)
        }

        let levels = SwiftSpectrumKernel.levels(forMonoSamples: samples, sampleRate: 48_000)

        XCTAssertEqual(levels.count, SwiftSpectrumKernel.bandCount)
        XCTAssertTrue(levels.allSatisfy { $0 >= 0 && $0 <= 1 })
        XCTAssertGreaterThan(levels.max() ?? 0, 0.3)
    }

    func testLevels_PeaksNearToneFrequency() {
        var samples = [Float](repeating: 0, count: 512)
        for index in samples.indices {
            samples[index] = 0.5 * sin(2 * .pi * Float(1000) * Float(index) / 48_000)
        }

        let levels = SwiftSpectrumKernel.levels(forMonoSamples: samples, sampleRate: 48_000)
        let peak = levels.enumerated().max(by: { $0.element < $1.element })?.offset

        // 1kHz lands around band 14 in the 32Hz...5kHz log layout.
        XCTAssertNotNil(peak)
        XCTAssertTrue((12 ... 16).contains(peak ?? -1), "peak band \(peak ?? -1) outside 12...16")
    }

    func testLevels_IsDeterministic() {
        var samples = [Float](repeating: 0, count: 512)
        for index in samples.indices {
            samples[index] = 0.3 * sin(2 * .pi * Float(220) * Float(index) / 48_000)
        }

        XCTAssertEqual(
            SwiftSpectrumKernel.levels(forMonoSamples: samples, sampleRate: 48_000),
            SwiftSpectrumKernel.levels(forMonoSamples: samples, sampleRate: 48_000)
        )
    }

    func testLevels_WithInvalidSampleRate_ReturnsEmpty() {
        XCTAssertEqual(
            SwiftSpectrumKernel.levels(forMonoSamples: [Float](repeating: 0.5, count: 512), sampleRate: 0),
            []
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

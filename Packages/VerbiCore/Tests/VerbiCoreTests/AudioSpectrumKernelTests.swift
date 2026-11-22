import Accelerate
import AVFoundation
@testable import VerbiCoreAudio
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
            samples[index] = 0.5 * sin(2 * .pi * Float(440) * Float(index) / 48000)
        }

        let levels = SwiftSpectrumKernel.levels(forMonoSamples: samples)

        XCTAssertEqual(levels.count, SwiftSpectrumKernel.bandCount)
        XCTAssertTrue(levels.allSatisfy { $0 >= 0 && $0 <= 1 })
        XCTAssertGreaterThan(levels.max() ?? 0, 0.3)
    }

    func testLevels_PeaksNearToneFrequency() {
        var samples = [Float](repeating: 0, count: 1536)
        for index in samples.indices {
            samples[index] = 0.5 * sin(2 * .pi * Float(1000) * Float(index) / 48000)
        }

        let levels = SwiftSpectrumKernel.levels(forMonoSamples: samples, sampleRate: 48000)
        let peak = levels.enumerated().max(by: { $0.element < $1.element })?.offset

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
            samples[index] = 0.3 * sin(2 * .pi * Float(220) * Float(index) / 48000)
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
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        buffer.frameLength = 512
        guard let channel = buffer.floatChannelData else {
            return XCTFail("Expected float channel data")
        }
        for frame in 0 ..< 512 {
            channel[0][frame] = 0.5 * sin(2 * .pi * Float(440) * Float(frame) / 48000)
        }

        let levels = kernel.levels(for: buffer)

        XCTAssertEqual(levels.count, SwiftSpectrumKernel.bandCount)
        XCTAssertGreaterThan(levels.max() ?? 0, 0.3)
    }

    func testLevelsForBuffer_WithEmptyBuffer_ReturnsEmpty() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        buffer.frameLength = 0

        XCTAssertEqual(kernel.levels(for: buffer), [])
    }

    func testLevels_MatchesUncachedReference_ForMultipleSampleCounts() {
        let cases: [(sampleRate: Double, toneHz: Float)] = [(16000, 440), (48000, 1000)]

        for (sampleRate, toneHz) in cases {
            let count = SwiftSpectrumKernel.sampleCount(forSampleRate: sampleRate)
            var samples = [Float](repeating: 0, count: count)
            for index in samples.indices {
                samples[index] = 0.5 * sin(2 * .pi * toneHz * Float(index) / Float(sampleRate))
            }
            let expected = uncachedLevels(forMonoSamples: samples, sampleRate: sampleRate)

            XCTAssertEqual(SwiftSpectrumKernel.levels(forMonoSamples: samples, sampleRate: sampleRate), expected)
            XCTAssertEqual(SwiftSpectrumKernel.levels(forMonoSamples: samples, sampleRate: sampleRate), expected)
        }
    }

    private func uncachedLevels(forMonoSamples samples: [Float], sampleRate: Double) -> [Float] {
        let bandCount = 21
        let sampleCount = SwiftSpectrumKernel.sampleCount(forSampleRate: sampleRate)
        let nyquist = sampleCount / 2
        var real = [Float](repeating: 0, count: sampleCount)
        for index in 0 ..< min(samples.count, sampleCount) {
            let window = 0.5 - 0.5 * cos(2 * .pi * Float(index) / Float(sampleCount - 1))
            real[index] = samples[index] * window
        }
        let imaginary = [Float](repeating: 0, count: sampleCount)
        var outputReal = [Float](repeating: 0, count: sampleCount)
        var outputImaginary = [Float](repeating: 0, count: sampleCount)
        guard let transform = try? vDSP.DiscreteFourierTransform(
            count: sampleCount,
            direction: .forward,
            transformType: .complexComplex,
            ofType: Float.self
        ) else { return [] }
        transform.transform(
            inputReal: real,
            inputImaginary: imaginary,
            outputReal: &outputReal,
            outputImaginary: &outputImaginary
        )
        let edges = (0 ... bandCount).map { band in
            let hz = 32.0 * pow(5000.0 / 32.0, Double(band) / Double(bandCount))
            return min(nyquist, Int(hz * Double(sampleCount) / sampleRate))
        }
        return (0 ..< bandCount).map { band in
            let lower = edges[band]
            let upper = max(lower + 1, edges[band + 1])
            var energy: Float = 0
            for bin in lower ..< min(upper, nyquist) {
                energy += outputReal[bin] * outputReal[bin] + outputImaginary[bin] * outputImaginary[bin]
            }
            let amplitude = sqrt(energy) / Float(sampleCount)
            let level = max(0, (sqrt(amplitude) - 0.025) * 15)
            return level / sqrt(1 + level * level)
        }
    }
}

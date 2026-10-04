import Accelerate
@preconcurrency import AVFoundation
import Foundation

/// Visualization-only frequency analysis for the recording waveform.
/// Stateless and `Sendable`: every call works from the given buffer alone
/// (last 512 mono frames, zero-padded), so the worker can reuse the shared
/// instance from its serial processing task with no locks.
/// Costs one 512-point DFT per meter snapshot (~24Hz, background task) —
/// never on the render tap, which only enqueues buffers.
protocol SpectrumKernel: Sendable {
    /// Returns `bandCount` normalized levels (0...1) or `[]` when unusable.
    func levels(for buffer: AVAudioPCMBuffer) -> [Float]
}

struct SwiftSpectrumKernel: SpectrumKernel {
    static let shared = SwiftSpectrumKernel()

    /// Analysis bands; same 21-band log layout as the reference,
    /// with bin edges pinned to its 16kHz capture rate.
    static let bandCount = 21
    private static let sampleCount = 512
    private static let referenceSampleRate = 16000.0
    private static let lowEdgeHz = 32.0
    private static let highEdgeHz = 5000.0
    private static let noiseFloor: Float = 0.025
    private static let levelGain: Float = 15

    /// Hann window shared by all calls.
    private static let window: [Float] = (0 ..< sampleCount).map {
        0.5 - 0.5 * cos(2 * .pi * Float($0) / Float(sampleCount - 1))
    }

    /// Log band edges in DFT bins, precomputed once like the reference.
    private static let edges: [Int] = (0 ... bandCount).map { band in
        let hz = lowEdgeHz * pow(highEdgeHz / lowEdgeHz, Double(band) / Double(bandCount))
        return min(sampleCount / 2, Int(hz * Double(sampleCount) / referenceSampleRate))
    }

    func levels(for buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard channelCount > 0, frameLength > 0, buffer.format.sampleRate > 0 else { return [] }
        let take = min(frameLength, Self.sampleCount)
        var mono = [Float](repeating: 0, count: take)
        for frame in 0 ..< take {
            var sum: Float = 0
            for channel in 0 ..< channelCount {
                sum += channelData[channel][frame + frameLength - take]
            }
            mono[frame] = sum / Float(channelCount)
        }
        return Self.levels(forMonoSamples: mono)
    }

    /// Pure analysis entry for deterministic tests.
    static func levels(forMonoSamples samples: [Float]) -> [Float] {
        var real = [Float](repeating: 0, count: sampleCount)
        for index in 0 ..< min(samples.count, sampleCount) {
            real[index] = samples[index] * window[index]
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
        let nyquist = sampleCount / 2
        return (0 ..< bandCount).map { band in
            let lower = edges[band]
            let upper = max(lower + 1, edges[band + 1])
            var energy: Float = 0
            for bin in lower ..< min(upper, nyquist) {
                energy += outputReal[bin] * outputReal[bin] + outputImaginary[bin] * outputImaginary[bin]
            }
            let amplitude = sqrt(energy) / Float(sampleCount)
            let level = max(0, (sqrt(amplitude) - noiseFloor) * levelGain)
            return level / sqrt(1 + level * level)
        }
    }
}

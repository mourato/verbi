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

    /// Analysis bands; same 21-band log layout as the reference (32Hz-5kHz).
    static let bandCount = 21
    private static let analysisWindowSeconds = 0.032
    /// DFT sizes vDSP accepts (f * 2^n, f in 1, 3); ~32ms covers 16-96kHz.
    private static let supportedSampleCounts = [512, 1024, 1536, 2048, 3072]
    private static let lowEdgeHz = 32.0
    private static let highEdgeHz = 5000.0
    private static let noiseFloor: Float = 0.025
    private static let levelGain: Float = 15

    /// Picks the DFT size closest to a 32ms window at the capture rate,
    /// matching the reference's 512 samples at 16kHz.
    static func sampleCount(forSampleRate sampleRate: Double) -> Int {
        let target = sampleRate * analysisWindowSeconds
        return supportedSampleCounts.min { abs(Double($0) - target) < abs(Double($1) - target) } ?? 512
    }

    func levels(for buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        let sampleRate = buffer.format.sampleRate
        guard channelCount > 0, frameLength > 0, sampleRate > 0 else { return [] }
        let take = min(frameLength, Self.sampleCount(forSampleRate: sampleRate))
        var mono = [Float](repeating: 0, count: take)
        for frame in 0 ..< take {
            var sum: Float = 0
            for channel in 0 ..< channelCount {
                sum += channelData[channel][frame + frameLength - take]
            }
            mono[frame] = sum / Float(channelCount)
        }
        return Self.levels(forMonoSamples: mono, sampleRate: sampleRate)
    }

    /// Pure analysis entry for deterministic tests. Band edges follow the
    /// real capture rate so 32Hz-5kHz holds at any device rate.
    static func levels(forMonoSamples samples: [Float], sampleRate: Double = 16000) -> [Float] {
        let sampleCount = sampleCount(forSampleRate: sampleRate)
        let nyquist = sampleCount / 2
        var real = [Float](repeating: 0, count: sampleCount)
        for index in 0 ..< min(samples.count, sampleCount) {
            let window = 0.5 - 0.5 * cos(2 * .pi * Float(index) / Float(sampleCount - 1))
            real[index] = samples[index] * window
        }
        let imaginary = [Float](repeating: 0, count: sampleCount)
        var outputReal = [Float](repeating: 0, count: sampleCount)
        var outputImaginary = [Float](repeating: 0, count: sampleCount)
        // ponytail: transform and window rebuilt per call (~24Hz, background);
        // cache per sample count if profiling shows it.
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
            let hz = lowEdgeHz * pow(highEdgeHz / lowEdgeHz, Double(band) / Double(bandCount))
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
            let level = max(0, (sqrt(amplitude) - noiseFloor) * levelGain)
            return level / sqrt(1 + level * level)
        }
    }
}

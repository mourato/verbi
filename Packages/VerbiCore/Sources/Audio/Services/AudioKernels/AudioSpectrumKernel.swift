import Accelerate
@preconcurrency import AVFoundation
import Foundation

protocol SpectrumKernel: Sendable {
    func levels(for buffer: AVAudioPCMBuffer) -> [Float]
}

struct SwiftSpectrumKernel: SpectrumKernel {
    static let shared = SwiftSpectrumKernel()

    static let bandCount = 21
    private static let analysisWindowSeconds = 0.032
    private static let supportedSampleCounts = [512, 1024, 1536, 2048, 3072]
    private static let lowEdgeHz = 32.0
    private static let highEdgeHz = 5000.0
    private static let noiseFloor: Float = 0.025
    private static let levelGain: Float = 15

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

@preconcurrency import AVFoundation
import Foundation

public protocol VoiceActivityKernel: Sendable {
    func setAdaptiveQualityMode(_ mode: RealtimeVoiceActivityWindowAssembler.AdaptiveQualityMode) async
    func append(buffer: AVAudioPCMBuffer) async throws -> [RealtimeVoiceActivityWindowAssembler.Window]
    func finish() async throws -> [RealtimeVoiceActivityWindowAssembler.Window]
}

extension RealtimeVoiceActivityWindowAssembler: VoiceActivityKernel {}

protocol EnergyMeterKernel: Sendable {
    func makeMeterSnapshot(from buffer: AVAudioPCMBuffer) -> AudioRecordingWorker.MeterSnapshot?
}

struct SwiftEnergyMeterKernel: EnergyMeterKernel {
    static let shared = SwiftEnergyMeterKernel()

    func makeMeterSnapshot(
        from buffer: AVAudioPCMBuffer
    ) -> AudioRecordingWorker.MeterSnapshot? {
        guard let channelData = buffer.floatChannelData else { return nil }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        let sampleRate = buffer.format.sampleRate
        guard channelCount > 0, frameLength > 0, sampleRate > 0 else { return nil }

        var maxRMS: Float = 0.0
        var maxPeak: Float = 0.0

        for channelIndex in 0 ..< channelCount {
            let channel = channelData[channelIndex]
            var sum: Float = 0.0
            var peak: Float = 0.0

            for frame in 0 ..< frameLength {
                let sample = abs(channel[frame])
                if sample > peak {
                    peak = sample
                }
                sum += sample * sample
            }

            let rms = sqrt(sum / Float(frameLength))
            if rms > maxRMS {
                maxRMS = rms
            }
            if peak > maxPeak {
                maxPeak = peak
            }
        }

        let averagePowerDB = Self.powerDB(fromLinear: maxRMS)
        let peakPowerDB = Self.powerDB(fromLinear: maxPeak)

        return AudioRecordingWorker.MeterSnapshot(
            averagePowerDB: averagePowerDB,
            peakPowerDB: peakPowerDB,
            deltaTime: Double(frameLength) / sampleRate
        )
    }

    static func powerDB(fromLinear value: Float) -> Float {
        20.0 * log10(max(value, 1e-10))
    }
}

protocol SilenceAnalysisKernel: Sendable {
    func analyze(inputURL: URL) throws -> AudioSilenceAnalysis
}

struct AudioSilenceAnalysis {
    let sampleRate: Double
    let totalFrames: AVAudioFramePosition
    let keepRanges: [Range<AVAudioFramePosition>]

    var durationSeconds: Double {
        guard sampleRate > 0 else { return 0 }
        return Double(totalFrames) / sampleRate
    }
}

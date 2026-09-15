import AVFoundation
import Combine
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

/// View model for audio playback and waveform visualization.
@MainActor
public final class AudioPlayerViewModel: ObservableObject {
    private enum Constants {
        static let playbackUpdateInterval: TimeInterval = 0.1
        static let timerToleranceRatio: Double = 0.25
        static let waveformSampleCount = 40
    }

    private var audioPlayer: AVAudioPlayer?
    private var timer: AnyCancellable?

    @Published public var isPlaying = false
    @Published public var currentTime: TimeInterval = 0
    @Published public var duration: TimeInterval = 0
    @Published public var samples: [Float] = []

    public init() {}

    /// Loads an audio file from a URL.
    public func loadAudio(url: URL) {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            audioPlayer = player
            duration = player.duration
            currentTime = 0
            isPlaying = false

            generateSamples(for: url)
        } catch {
            print("Failed to load audio for playback: \(error)")
        }
    }

    /// Toggles between play and pause.
    public func togglePlayback() {
        guard let player = audioPlayer else { return }

        if player.isPlaying {
            player.pause()
            stopTimer()
        } else {
            // If finished, reset to start
            if player.currentTime >= player.duration - 0.1 {
                player.currentTime = 0
            }
            player.play()
            startTimer()
        }
        isPlaying = player.isPlaying
    }

    /// Seeks to a specific time in the audio file.
    public func seek(to progress: Double) {
        guard let player = audioPlayer else { return }
        let targetTime = progress * duration
        player.currentTime = targetTime
        currentTime = targetTime
    }

    private func startTimer() {
        timer = Timer.publish(
            every: Constants.playbackUpdateInterval,
            tolerance: Constants.playbackUpdateInterval * Constants.timerToleranceRatio,
            on: .main,
            in: .common
        )
        .autoconnect()
        .sink { [weak self] _ in
            guard let self, let player = audioPlayer else { return }
            currentTime = player.currentTime
            if !player.isPlaying {
                isPlaying = false
                stopTimer()
            }
        }
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func generateSamples(for url: URL) {
        let extractedURL = url
        Task { @MainActor [weak self] in
            let extracted = await Task.detached(priority: .utility) {
                Self.extractWaveformSamples(from: extractedURL, count: Constants.waveformSampleCount)
            }.value
            self?.samples = extracted
        }
    }

    private nonisolated static func extractWaveformSamples(from url: URL, count: Int) -> [Float] {
        let fallback = [Float](repeating: 0.3, count: count)
        guard count > 0 else { return fallback }

        do {
            let audioFile = try AVAudioFile(forReading: url)
            let totalFrames = AVAudioFrameCount(audioFile.length)
            guard totalFrames > 0 else { return fallback }

            guard let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: audioFile.processingFormat.sampleRate,
                channels: 1,
                interleaved: false
            ) else { return fallback }

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
                return fallback
            }

            try audioFile.read(into: buffer)
            guard let channelData = buffer.floatChannelData?.pointee else { return fallback }

            let totalFrameCount = Int(totalFrames)
            var rmsValues = [Float]()
            rmsValues.reserveCapacity(count)

            for sampleIndex in 0 ..< count {
                let start = Int((Double(sampleIndex) / Double(count)) * Double(totalFrameCount))
                let nominalEnd = Int((Double(sampleIndex + 1) / Double(count)) * Double(totalFrameCount))
                let end = min(totalFrameCount, max(start + 1, nominalEnd))
                guard start < end else {
                    rmsValues.append(0)
                    continue
                }

                var sumOfSquares: Float = 0
                for frame in start ..< end {
                    let value = channelData[frame]
                    sumOfSquares += value * value
                }
                let rms = sqrtf(sumOfSquares / Float(end - start))
                rmsValues.append(rms)
            }

            let maxRMS = rmsValues.max() ?? 1
            guard maxRMS > 0 else { return fallback }

            return rmsValues.map { min(max($0 / maxRMS, 0.05), 1.0) }

        } catch {
            return fallback
        }
    }
}

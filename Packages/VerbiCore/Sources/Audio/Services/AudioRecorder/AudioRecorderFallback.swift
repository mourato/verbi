@preconcurrency import AVFoundation
import Foundation
import VerbiCoreCommon

// MARK: - Fallback Microphone Recorder

extension AudioRecorder {
    func startFallbackRecorder(to outputURL: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: Constants.fallbackSampleRate,
            AVNumberOfChannelsKey: Constants.fallbackChannels,
            AVEncoderBitRateKey: Constants.fallbackBitRate
        ]

        let recorder = try AVAudioRecorder(url: outputURL, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.record()
        fallbackRecorder = recorder
        isRecording = true

        fallbackMeterTimer?.invalidate()
        fallbackMeterTimer = Timer.scheduledTimer(withTimeInterval: Constants.fallbackMeterUpdateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateFallbackMeters()
            }
        }
        fallbackMeterTimer?.tolerance = Constants.fallbackMeterUpdateInterval * Constants.fallbackMeterTimerToleranceRatio

        AppLogger.info("Fallback mic recorder started", category: .recordingManager, extra: ["path": outputURL.path])
    }

    func stopFallbackRecorder(_ recorder: AVAudioRecorder) {
        fallbackMeterTimer?.invalidate()
        fallbackMeterTimer = nil
        lastMeterSnapshotDate = nil
        latestMeterSnapshot = nil

        recorder.stop()
        fallbackRecorder = nil

        AppLogger.info("Fallback mic recorder stopped", category: .recordingManager, extra: ["path": recorder.url.path])
    }

    @MainActor
    func updateFallbackMeters() {
        guard let recorder = fallbackRecorder else { return }
        recorder.updateMeters()
        publishMeterSnapshot(
            averagePower: recorder.averagePower(forChannel: 0),
            peakPower: recorder.peakPower(forChannel: 0)
        )
    }
}

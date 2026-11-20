@preconcurrency import AVFoundation
import Foundation
import VerbiCoreCommon

// MARK: - Fallback Microphone Recorder

extension AudioRecorder {
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

extension AudioRecorder {
    /// AVAudioRecorder settings whose encoding matches the output file's container.
    /// AAC into a .wav file fails with kAudioFormatUnsupportedDataFormatError ('fmt?').
    nonisolated static func recorderSettings(
        for outputURL: URL,
        sampleRate: Double,
        channels: Int,
        aacSettings: [String: Any]
    ) -> [String: Any] {
        var settings: [String: Any] = [AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: channels]
        if outputURL.pathExtension.lowercased() == "wav" {
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 16
        } else {
            settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            settings.merge(aacSettings) { _, new in new }
        }
        return settings
    }
}

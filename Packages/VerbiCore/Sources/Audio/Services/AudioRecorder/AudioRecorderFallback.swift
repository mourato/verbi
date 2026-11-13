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

import AppKit
@preconcurrency import AVFoundation
import Combine
import CoreAudio
import Foundation
import os.log
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

struct InputDeviceOverride {
    let originalDeviceID: AudioObjectID?
    let targetDeviceID: AudioObjectID
}

extension MeetingRecorder {
    func applyPreferredInputDeviceOverride() -> InputDeviceOverride? {
        guard !AppSettingsStore.shared.useSystemDefaultInput else {
            AppLogger.debug("Using engine-managed default input device", category: .recordingManager)
            return nil
        }

        let preferredUID = microphoneInputSelectionResolver.preferredCustomMicrophoneUID()
        guard let customDeviceID = microphoneInputSelectionResolver.resolveCustomMicrophoneDeviceID() else {
            AppLogger.debug(
                "No usable custom input device for current power state. Keeping system default.",
                category: .recordingManager,
                extra: [
                    "powerSource": microphoneInputSelectionResolver.currentPowerSourceState().rawValue,
                    "preferredUID": preferredUID ?? "nil"
                ]
            )
            return nil
        }

        if let systemDefaultID = deviceManager.getDefaultInputDeviceIDRaw(),
           customDeviceID == systemDefaultID
        {
            AppLogger.info(
                "Custom input selection matches system default. No override needed.",
                category: .recordingManager,
                extra: [
                    "deviceID": customDeviceID,
                    "preferredUID": preferredUID ?? "nil",
                    "powerSource": microphoneInputSelectionResolver.currentPowerSourceState().rawValue
                ]
            )
            return nil
        }

        let originalDefaultID = deviceManager.getSystemDefaultInputDeviceID()

        let didSet = deviceManager.setSystemDefaultInputDevice(customDeviceID)
        if didSet {
            let deviceName = deviceManager.getDeviceName(for: customDeviceID) ?? "Unknown"
            AppLogger.info(
                "Temporarily set system default input to preferred custom mic",
                category: .recordingManager,
                extra: [
                    "deviceID": customDeviceID,
                    "deviceName": deviceName,
                    "preferredUID": preferredUID ?? "nil",
                    "powerSource": microphoneInputSelectionResolver.currentPowerSourceState().rawValue,
                    "originalDefaultID": originalDefaultID as Any
                ]
            )
            logDeviceDiagnostics(for: customDeviceID, label: "customMicOverride")
            return InputDeviceOverride(originalDeviceID: originalDefaultID, targetDeviceID: customDeviceID)
        } else {
            AppLogger.warning(
                "Failed to set system default input device. Engine will use current default.",
                category: .recordingManager,
                extra: ["deviceID": customDeviceID, "preferredUID": preferredUID ?? "nil"]
            )
            return nil
        }
    }

    func restoreSystemDefaultInputDevice(_ originalDeviceID: AudioObjectID?) {
        guard let originalID = originalDeviceID else { return }

        let didRestore = deviceManager.setSystemDefaultInputDevice(originalID)
        if didRestore {
            AppLogger.info(
                "Restored system default input device after engine start",
                category: .recordingManager,
                extra: ["restoredDeviceID": originalID]
            )
        } else {
            AppLogger.warning(
                "Failed to restore original system default input device",
                category: .recordingManager,
                extra: ["targetDeviceID": originalID]
            )
        }
    }
}

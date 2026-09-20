import AppKit
@preconcurrency import AVFoundation
import Combine
import CoreAudio
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import os.log

extension AudioRecorder {
    // MARK: - System Default Input Override

    /// Applies the preferred custom microphone by temporarily overriding the system
    /// default input device **before** the engine is initialized.
    ///
    /// This approach avoids using `kAudioOutputUnitProperty_CurrentDevice` on the
    /// AUHAL, which changes the I/O unit device for BOTH input and output, forcing
    /// macOS to create an aggregate device. Aggregate devices are fragile —
    /// especially with Bluetooth headphones in SCO (call) mode — and cause
    /// cascading IO context and engine initialization failures.
    ///
    /// The flow:
    /// 1. Save the current system default input device ID.
    /// 2. Set the system default input to the preferred custom mic.
    /// 3. Return the original ID so the caller can restore it after the engine starts.
    ///
    /// - Returns: The original system default input device ID to restore later,
    ///   or `nil` if no override was applied (system default should be used).
    func applyPreferredInputDeviceOverride() -> AudioObjectID? {
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

        // If the custom device is already the system default, no override needed.
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

        // Capture the original system default before overriding.
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
            return originalDefaultID
        } else {
            AppLogger.warning(
                "Failed to set system default input device. Engine will use current default.",
                category: .recordingManager,
                extra: ["deviceID": customDeviceID, "preferredUID": preferredUID ?? "nil"]
            )
            return nil
        }
    }

    /// Restores the system default input device after the engine has started.
    ///
    /// Once `AVAudioEngine` is running, it has latched onto the input device and
    /// changing the system default will not affect the running engine. This restores
    /// the original default so other apps are not affected.
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

import Foundation
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

extension AudioRecorder {
    func startMicrophoneCaptureSession(
        _ capture: some MicrophoneCaptureSessionProtocol,
        preferredUID: String?
    ) async throws {
        activeMicrophoneDeviceName = nil
        activeMicrophoneDidFallBackToDefault = false
        let result = try await capture.start(deviceUID: preferredUID)
        activeMicrophoneDeviceName = result.activeDeviceName
        activeMicrophoneDidFallBackToDefault = result.requestedDeviceUID != nil && !result.usedRequestedDevice
    }

    func preferredMicrophoneCaptureUID() -> String? {
        guard !AppSettingsStore.shared.useSystemDefaultInput,
              let deviceID = microphoneInputSelectionResolver.resolveCustomMicrophoneDeviceID()
        else { return nil }
        return deviceManager.getDeviceUID(for: deviceID)
    }
}

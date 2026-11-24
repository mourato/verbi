import Foundation
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

extension DictationRecorder {
    func startMicrophoneCaptureSession(
        _ capture: some MicrophoneCaptureSessionProtocol,
        preferredUID: String?
    ) async throws {
        activeMicrophoneDeviceName = nil
        activeMicrophoneDidFallBackToDefault = false
        let result = try await capture.start(deviceUID: preferredUID)
        activeMicrophoneDeviceName = result.activeDeviceName
        activeMicrophoneDidFallBackToDefault = result.didFallBackToDefault
    }

    func preferredMicrophoneCaptureUID() -> String? {
        microphoneInputSelectionResolver.preferredCustomMicrophoneUID()
    }
}

import AVFoundation
import Foundation
import VerbiCoreCommon

public final class AudioHealthMonitor: Sendable {
    public init() {}

    public func checkHealth() -> HealthStatus {
        var issues: [String] = []

        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if authStatus != .authorized {
            issues.append("Microphone permission status: \(authStatusCode(authStatus))")
        }

        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        let inputAvailable = !discoverySession.devices.isEmpty

        if !inputAvailable {
            issues.append("No audio input available on device")
        }

        if issues.isEmpty {
            AppLogger.info("Audio System Healthy", category: .health)
            return .healthy
        } else {
            let issueStr = issues.joined(separator: ", ")
            AppLogger.warning("Audio System Unhealthy: \(issueStr)", category: .health)
            return .unhealthy(reasons: issues)
        }
    }

    private func authStatusCode(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: "Authorized"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Not Determined"
        @unknown default: "Unknown"
        }
    }

    public enum HealthStatus: Equatable {
        case healthy
        case unhealthy(reasons: [String])
    }
}

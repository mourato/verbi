import AVFoundation
import Foundation
import MeetingAssistantCoreCommon

/// Monitors the health status of the audio subsystem
public final class AudioHealthMonitor: Sendable {
    public init() {}

    /// Check current audio system health
    public func checkHealth() -> HealthStatus {
        var issues: [String] = []

        // 1. Check Permissions
        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if authStatus != .authorized {
            issues.append("Microphone permission status: \(authStatusCode(authStatus))")
        }

        // 2. Check Input Availability
        // 2. Check Input Availability
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        let inputAvailable = !discoverySession.devices.isEmpty

        if !inputAvailable {
            issues.append("No audio input available on device")
        }

        // 3. Log Status
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
        case .authorized: return "Authorized"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not Determined"
        @unknown default: return "Unknown"
        }
    }

    public enum HealthStatus: Equatable {
        case healthy
        case unhealthy(reasons: [String])
    }
}

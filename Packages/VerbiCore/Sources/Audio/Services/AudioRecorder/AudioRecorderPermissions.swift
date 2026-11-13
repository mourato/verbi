import AppKit
@preconcurrency import AVFoundation
import VerbiCoreDomain

public extension AudioRecorder {
    func hasPermission() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func getPermissionState() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .denied: .denied
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        @unknown default: .notDetermined
        }
    }

    func requestPermission() async {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}

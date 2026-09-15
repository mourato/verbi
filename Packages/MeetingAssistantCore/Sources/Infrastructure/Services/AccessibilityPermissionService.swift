import AppKit
@preconcurrency import ApplicationServices
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain

@MainActor
public enum AccessibilityPermissionService {
    public static func currentState() -> PermissionState {
        isTrusted() ? .granted : .denied
    }

    public static func requestPermission() {
        // Avoid system permission popups during XCTest execution.
        if AppIdentity.isRunningTests {
            _ = AXIsProcessTrusted()
            return
        }

        let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public static func openSystemSettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    public static func isTrusted() -> Bool {
        withUnsafeCurrentTask { _ in
            AXIsProcessTrusted()
        }
    }
}

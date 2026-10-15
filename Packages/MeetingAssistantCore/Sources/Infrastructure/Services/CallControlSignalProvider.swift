import AppKit
import ApplicationServices
import Foundation
import MeetingAssistantCoreDomain

/// Represents the call state of a meeting application.
public enum CallState: Sendable, Equatable {
    case inCall
    case ended
    case inconclusive
}

/// Protocol providing call control status signals for meeting applications.
public protocol CallControlSignalProviding: Sendable {
    func evaluateCallState(for pid: pid_t, app: MeetingApp) async -> CallState
}

/// Default implementation inspecting the Accessibility hierarchy of the meeting application.
public final class AccessibilityCallControlProvider: CallControlSignalProviding {
    public typealias CustomInspector = @Sendable (pid_t, MeetingApp) async -> CallState?

    private let customInspector: CustomInspector?

    public init(customInspector: CustomInspector? = nil) {
        self.customInspector = customInspector
    }

    public func evaluateCallState(for pid: pid_t, app: MeetingApp) async -> CallState {
        if let customInspector, let customState = await customInspector(pid, app) {
            return customState
        }

        guard AXIsProcessTrusted() else {
            return .inconclusive
        }

        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 1.0)

        var windowsRef: CFTypeRef?
        let copyResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard copyResult == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
            return .inconclusive
        }

        switch app {
        case .zoom:
            return evaluateZoom(windows: windows)
        case .microsoftTeams:
            return evaluateTeams(windows: windows)
        case .googleMeet:
            return evaluateGoogleMeet(windows: windows)
        case .slack, .discord, .whatsApp, .manualMeeting, .importedFile, .unknown:
            return evaluateGenericCallApp(windows: windows)
        }
    }

    // MARK: - App Specific AX Inspectors

    private func evaluateZoom(windows: [AXUIElement]) -> CallState {
        // Zoom meeting window typically has "Zoom Meeting" in title or an End/Leave button.
        var hasMeetingWindow = false
        var hasEndOrLeaveButton = false
        var hasEndedIndication = false

        for window in windows {
            let title = stringAttribute(kAXTitleAttribute as CFString, from: window) ?? ""
            if title.localizedStandardContains("Zoom Meeting") ||
                title.localizedStandardContains("Meeting")
            {
                hasMeetingWindow = true
            }

            if containsElement(matching: ["End", "Leave"], in: window, maxDepth: 4) {
                hasEndOrLeaveButton = true
            }

            if title.localizedStandardContains("Meeting ended") ||
                containsElement(matching: ["Meeting ended", "The meeting has ended", "You left the meeting"], in: window, maxDepth: 3)
            {
                hasEndedIndication = true
            }
        }

        if hasEndedIndication {
            return .ended
        }

        if hasMeetingWindow || hasEndOrLeaveButton {
            return .inCall
        }

        // Absence of recognized control or meeting window is inconclusive, NEVER ended
        return .inconclusive
    }

    private func evaluateTeams(windows: [AXUIElement]) -> CallState {
        var hasEndedIndication = false
        for window in windows {
            if containsElement(matching: ["Leave call", "Hang up", "Leave", "End call"], in: window, maxDepth: 4) {
                return .inCall
            }
            if containsElement(matching: ["Meeting ended", "Call ended", "You left the call"], in: window, maxDepth: 3) {
                hasEndedIndication = true
            }
        }
        if hasEndedIndication {
            return .ended
        }
        // Absence of recognized control is inconclusive, NEVER ended
        return .inconclusive
    }

    private func evaluateGoogleMeet(windows: [AXUIElement]) -> CallState {
        var hasEndedIndication = false
        for window in windows {
            if containsElement(matching: ["Leave call", "Leave meeting"], in: window, maxDepth: 5) {
                return .inCall
            }
            if containsElement(matching: ["You left the meeting", "Meeting ended", "Call ended"], in: window, maxDepth: 4) {
                hasEndedIndication = true
            }
        }
        if hasEndedIndication {
            return .ended
        }
        // Browser windows may remain open after meet ends.
        return .inconclusive
    }

    private func evaluateGenericCallApp(windows: [AXUIElement]) -> CallState {
        var hasEndedIndication = false
        for window in windows {
            if containsElement(matching: ["Leave", "Hang up", "End call"], in: window, maxDepth: 3) {
                return .inCall
            }
            if containsElement(matching: ["Call ended", "Meeting ended"], in: window, maxDepth: 3) {
                hasEndedIndication = true
            }
        }
        if hasEndedIndication {
            return .ended
        }
        return .inconclusive
    }

    // MARK: - AX Traversal Helpers

    private func containsElement(matching terms: [String], in element: AXUIElement, maxDepth: Int) -> Bool {
        guard maxDepth > 0 else { return false }

        let title = stringAttribute(kAXTitleAttribute as CFString, from: element) ?? ""
        let description = stringAttribute(kAXDescriptionAttribute as CFString, from: element) ?? ""

        for term in terms where title.localizedStandardContains(term) || description.localizedStandardContains(term) {
            return true
        }

        var childrenRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        guard result == .success, let children = childrenRef as? [AXUIElement] else {
            return false
        }

        for child in children where containsElement(matching: terms, in: child, maxDepth: maxDepth - 1) {
            return true
        }

        return false
    }

    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard result == .success, let value = valueRef else { return nil }
        return value as? String
    }
}

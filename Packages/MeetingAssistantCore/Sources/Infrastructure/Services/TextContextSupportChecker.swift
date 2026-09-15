import AppKit
@preconcurrency import ApplicationServices
import Foundation
import MeetingAssistantCoreDomain

public enum TextContextSupportStatus: String, Sendable {
    case unknown
    case supported
    case permissionDenied
    case noActiveApp
    case noFocusedElement
    case unsupported
}

@MainActor
public final class TextContextSupportChecker {
    private let textMarkerRangeAttribute: CFString = "AXTextMarkerRange" as CFString
    private let activeAppProvider: ActiveAppContextProvider

    public init(activeAppProvider: ActiveAppContextProvider = NSWorkspaceActiveAppContextProvider()) {
        self.activeAppProvider = activeAppProvider
    }

    public func checkSupport() async -> TextContextSupportStatus {
        guard AccessibilityPermissionService.isTrusted() else {
            return .permissionDenied
        }

        let appContext: ActiveAppContext?
        do {
            appContext = try await activeAppProvider.fetchActiveAppContext()
        } catch {
            return .noActiveApp
        }

        guard let appContext else {
            return .noActiveApp
        }

        let appElement = AXUIElementCreateApplication(pid_t(appContext.processIdentifier))
        var focusedElementRef: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )

        guard focusedResult == .success,
              let focusedElementRef,
              CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID()
        else {
            return .noFocusedElement
        }

        let focusedElement = unsafeDowncast(focusedElementRef, to: AXUIElement.self)

        if supportsTextMarkerRange(focusedElement) || supportsVisibleRange(focusedElement) {
            return .supported
        }

        return .unsupported
    }

    private func supportsTextMarkerRange(_ element: AXUIElement) -> Bool {
        var markerRangeRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            textMarkerRangeAttribute,
            &markerRangeRef
        )
        return result == .success
    }

    private func supportsVisibleRange(_ element: AXUIElement) -> Bool {
        var visibleRangeRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXVisibleCharacterRangeAttribute as CFString,
            &visibleRangeRef
        )
        return result == .success
    }
}

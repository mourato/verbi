import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation
import MeetingAssistantCoreCommon
@preconcurrency import ScreenCaptureKit
import Vision

public struct ContextAwarenessCaptureOptions: Sendable {
    public let includeActiveApp: Bool
    public let includeClipboard: Bool
    public let includeWindowOCR: Bool
    public let includeAccessibilityText: Bool
    public let protectSensitiveApps: Bool
    public let redactSensitiveData: Bool
    public let excludedBundleIDs: [String]

    public init(
        includeActiveApp: Bool,
        includeClipboard: Bool,
        includeWindowOCR: Bool,
        includeAccessibilityText: Bool,
        protectSensitiveApps: Bool,
        redactSensitiveData: Bool,
        excludedBundleIDs: [String]
    ) {
        self.includeActiveApp = includeActiveApp
        self.includeClipboard = includeClipboard
        self.includeWindowOCR = includeWindowOCR
        self.includeAccessibilityText = includeAccessibilityText
        self.protectSensitiveApps = protectSensitiveApps
        self.redactSensitiveData = redactSensitiveData
        self.excludedBundleIDs = excludedBundleIDs
    }
}

public struct ContextAwarenessSnapshot: Sendable {
    public let activeAppName: String?
    public let activeWindowTitle: String?
    public let activeAccessibilityText: String?
    public let clipboardText: String?
    public let activeWindowOCRText: String?

    public var hasContent: Bool {
        activeAppName != nil || activeWindowTitle != nil || activeAccessibilityText != nil || clipboardText != nil || activeWindowOCRText != nil
    }

    public init(
        activeAppName: String?,
        activeWindowTitle: String?,
        activeAccessibilityText: String?,
        clipboardText: String?,
        activeWindowOCRText: String?
    ) {
        self.activeAppName = activeAppName
        self.activeWindowTitle = activeWindowTitle
        self.activeAccessibilityText = activeAccessibilityText
        self.clipboardText = clipboardText
        self.activeWindowOCRText = activeWindowOCRText
    }
}

@MainActor
public protocol ContextAwarenessServiceProtocol: Sendable {
    func captureSnapshot(options: ContextAwarenessCaptureOptions) async -> ContextAwarenessSnapshot
    func makePostProcessingContext(from snapshot: ContextAwarenessSnapshot) -> String?
}

@MainActor
public final class ContextAwarenessService: ContextAwarenessServiceProtocol {
    public static let shared = ContextAwarenessService()

    private enum Constants {
        static let maxClipboardCharacters = 2000
        static let maxOCRCharacters = 4000
        static let maxAccessibilityCharacters = 4000
        static let maxWindowTitleCharacters = 500
        static let maxAppNameCharacters = 200
        static let maxExcludedBundleIDs = 100
    }

    public init() {}

    public func captureSnapshot(options: ContextAwarenessCaptureOptions) async -> ContextAwarenessSnapshot {
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let frontmostBundleID = frontmostApp?.bundleIdentifier ?? "unknown"

        if options.protectSensitiveApps,
           ContextAwarenessPrivacy.isCaptureBlocked(bundleIdentifier: frontmostApp?.bundleIdentifier, excludedBundleIDs: options.excludedBundleIDs)
        {
            AppLogger.info(
                "Context capture blocked for sensitive app",
                category: .recordingManager,
                extra: [
                    "reasonCode": "context.sensitive_app_blocked",
                    "bundleID": frontmostBundleID
                ]
            )
            return ContextAwarenessSnapshot(
                activeAppName: nil,
                activeWindowTitle: nil,
                activeAccessibilityText: nil,
                clipboardText: nil,
                activeWindowOCRText: nil
            )
        }

        let activeApp = options.includeActiveApp ? frontmostApp : nil
        var appName = activeApp?.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        var windowTitle = options.includeActiveApp ? focusedWindowTitle(for: activeApp) : nil
        var accessibilityText = options.includeAccessibilityText ? focusedElementText(for: activeApp) : nil
        var clipboard = options.includeClipboard ? readClipboardText() : nil
        var ocrText = options.includeWindowOCR ? await readActiveWindowOCRText(for: activeApp) : nil

        if options.redactSensitiveData {
            appName = ContextAwarenessPrivacy.redactSensitiveText(appName)
            windowTitle = ContextAwarenessPrivacy.redactSensitiveText(windowTitle)
            accessibilityText = ContextAwarenessPrivacy.redactSensitiveText(accessibilityText)
            clipboard = ContextAwarenessPrivacy.redactSensitiveText(clipboard)
            ocrText = ContextAwarenessPrivacy.redactSensitiveText(ocrText)
        }

        return ContextAwarenessSnapshot(
            activeAppName: nonEmpty(limited(appName, maxCharacters: Constants.maxAppNameCharacters)),
            activeWindowTitle: nonEmpty(limited(windowTitle, maxCharacters: Constants.maxWindowTitleCharacters)),
            activeAccessibilityText: nonEmpty(limited(accessibilityText, maxCharacters: Constants.maxAccessibilityCharacters)),
            clipboardText: nonEmpty(clipboard),
            activeWindowOCRText: nonEmpty(ocrText)
        )
    }

    public func makePostProcessingContext(from snapshot: ContextAwarenessSnapshot) -> String? {
        guard snapshot.hasContent else { return nil }

        var lines: [String] = []
        lines.append("CONTEXT_METADATA")

        if let activeAppName = snapshot.activeAppName {
            appendTaggedContext("ACTIVE_APP", activeAppName, to: &lines)
        }

        if let activeWindowTitle = snapshot.activeWindowTitle {
            appendTaggedContext("WINDOW_TITLE", activeWindowTitle, to: &lines)
        }

        if let activeAccessibilityText = snapshot.activeAccessibilityText {
            appendTaggedContext("FOCUSED_UI_TEXT", activeAccessibilityText, to: &lines)
        }

        if let clipboardText = snapshot.clipboardText {
            appendTaggedContext("CLIPBOARD_CONTEXT", clipboardText, to: &lines)
        }

        if let activeWindowOCRText = snapshot.activeWindowOCRText {
            appendTaggedContext("WINDOW_OCR_CONTEXT", activeWindowOCRText, to: &lines)
        }

        return lines.joined(separator: "\n")
    }

    private func appendTaggedContext(_ tag: String, _ value: String, to lines: inout [String]) {
        lines.append("<\(tag)>")
        lines.append(value)
        lines.append("</\(tag)>")
    }

    private func focusedWindowTitle(for app: NSRunningApplication?) -> String? {
        guard let app else { return nil }
        guard AccessibilityPermissionService.isTrusted() else { return nil }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindow: CFTypeRef?
        let focusedWindowResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )

        guard focusedWindowResult == .success, let focusedWindow else {
            return nil
        }

        guard CFGetTypeID(focusedWindow) == AXUIElementGetTypeID() else {
            return nil
        }
        let windowElement = unsafeDowncast(focusedWindow, to: AXUIElement.self)

        var titleValue: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(
            windowElement,
            kAXTitleAttribute as CFString,
            &titleValue
        )

        guard titleResult == .success else { return nil }
        return titleValue as? String
    }

    private func focusedElementText(for app: NSRunningApplication?) -> String? {
        guard let app else { return nil }
        guard AccessibilityPermissionService.isTrusted() else { return nil }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedElementRef: CFTypeRef?
        let focusedElementResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )

        guard focusedElementResult == .success, let focusedElementRef else { return nil }
        guard CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID() else { return nil }
        let focusedElement = unsafeDowncast(focusedElementRef, to: AXUIElement.self)

        if let selectedText = readAXStringAttribute(focusedElement, attribute: kAXSelectedTextAttribute as String) {
            return selectedText
        }

        if let valueText = readAXStringAttribute(focusedElement, attribute: kAXValueAttribute as String) {
            return valueText
        }

        if let titleText = readAXStringAttribute(focusedElement, attribute: kAXTitleAttribute as String) {
            return titleText
        }

        if let descriptionText = readAXStringAttribute(focusedElement, attribute: kAXDescriptionAttribute as String) {
            return descriptionText
        }

        return nil
    }

    private func readClipboardText() -> String? {
        guard let value = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }

        if value.count <= Constants.maxClipboardCharacters {
            return value
        }

        let maxEndIndex = value.index(value.startIndex, offsetBy: Constants.maxClipboardCharacters)
        return String(value[..<maxEndIndex])
    }

    private func readAXStringAttribute(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value else { return nil }

        if let stringValue = value as? String {
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let attributedString = value as? NSAttributedString {
            let trimmed = attributedString.string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return nil
    }

    private func readActiveWindowOCRText(for app: NSRunningApplication?) async -> String? {
        guard CGPreflightScreenCaptureAccess() else {
            AppLogger.warning(
                "OCR capture skipped: screen recording permission not granted",
                category: .recordingManager,
                extra: ["reasonCode": "ocr.permission_denied"]
            )
            return nil
        }

        guard let app else {
            AppLogger.debug(
                "OCR capture skipped: no active app",
                category: .recordingManager,
                extra: ["reasonCode": "ocr.no_active_app"]
            )
            return nil
        }

        guard let windowID = frontmostWindowID(for: app.processIdentifier) else {
            AppLogger.debug(
                "OCR capture skipped: no frontmost window found",
                category: .recordingManager,
                extra: [
                    "reasonCode": "ocr.no_frontmost_window",
                    "bundleID": app.bundleIdentifier ?? "unknown",
                    "pid": app.processIdentifier
                ]
            )
            return nil
        }

        let image = await captureWindowImageUsingScreenCaptureKit(windowID: windowID)

        guard let image else {
            AppLogger.debug(
                "OCR capture skipped: failed to capture window image",
                category: .recordingManager,
                extra: ["reasonCode": "ocr.image_capture_failed"]
            )
            return nil
        }

        let text = recognizedText(from: image)
        if text == nil {
            AppLogger.debug(
                "OCR capture finished with empty text",
                category: .recordingManager,
                extra: ["reasonCode": "ocr.empty_text"]
            )
        }
        return text
    }

    @available(macOS 14.0, *)
    private nonisolated func captureWindowImageUsingScreenCaptureKit(windowID: CGWindowID) async -> CGImage? {
        do {
            let content = try await SCShareableContent.current
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                AppLogger.debug(
                    "OCR image capture skipped: window no longer available",
                    category: .recordingManager,
                    extra: [
                        "reasonCode": "ocr.window_unavailable",
                        "windowID": windowID
                    ]
                )
                return nil
            }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width)
            config.height = Int(window.frame.height)

            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
        } catch {
            AppLogger.warning(
                "OCR image capture failed",
                category: .recordingManager,
                extra: [
                    "reasonCode": "ocr.screencapturekit_error",
                    "windowID": windowID
                ]
            )
            return nil
        }
    }

    private func frontmostWindowID(for processIdentifier: pid_t) -> CGWindowID? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for info in windowList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == processIdentifier
            else {
                continue
            }

            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            if layer != 0 {
                continue
            }

            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            if alpha <= 0 {
                continue
            }

            if let idNumber = info[kCGWindowNumber as String] as? NSNumber {
                return CGWindowID(idNumber.uint32Value)
            }
        }

        return nil
    }

    private func recognizedText(from image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            AppLogger.warning(
                "OCR recognition request failed",
                category: .recordingManager,
                extra: [
                    "reasonCode": "ocr.vision_request_failed",
                    "error": error.localizedDescription
                ]
            )
            return nil
        }

        let observations = request.results ?? []
        let text = observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return nil }
        if text.count <= Constants.maxOCRCharacters {
            return text
        }

        let maxEndIndex = text.index(text.startIndex, offsetBy: Constants.maxOCRCharacters)
        return String(text[..<maxEndIndex])
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func limited(_ value: String?, maxCharacters: Int) -> String? {
        guard let value else { return nil }
        guard value.count > maxCharacters else { return value }

        let endIndex = value.index(value.startIndex, offsetBy: maxCharacters)
        return String(value[..<endIndex])
    }
}

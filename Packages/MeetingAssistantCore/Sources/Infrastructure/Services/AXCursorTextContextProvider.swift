import AppKit
@preconcurrency import ApplicationServices
import Foundation
import MeetingAssistantCoreDomain

@MainActor
public final class AXCursorTextContextProvider: CursorTextContextProvider {
    public init() {}

    public func fetchCursorTextContext() -> CursorTextContext {
        guard AccessibilityPermissionService.isTrusted() else {
            return CursorTextContext(
                previousCharacter: nil,
                nextCharacter: nil,
                isEmptyDocument: false,
                support: .permissionDenied
            )
        }

        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication,
              frontmostApplication.processIdentifier != 0
        else {
            return unsupportedContext()
        }

        do {
            let focusedElement = try focusedElement(for: Int(frontmostApplication.processIdentifier))
            guard let selectedRange = selectedRange(from: focusedElement) else {
                return unsupportedContext()
            }

            let previousCharacter = character(at: selectedRange.location - 1, in: focusedElement)
            let nextCharacter = character(at: selectedRange.location + selectedRange.length, in: focusedElement)
            let isEmptyDocument = documentLength(from: focusedElement) == 0

            return CursorTextContext(
                previousCharacter: previousCharacter,
                nextCharacter: nextCharacter,
                isEmptyDocument: isEmptyDocument,
                support: .supported
            )
        } catch {
            return unsupportedContext()
        }
    }

    private func unsupportedContext() -> CursorTextContext {
        CursorTextContext(
            previousCharacter: nil,
            nextCharacter: nil,
            isEmptyDocument: false,
            support: .unsupported
        )
    }

    private func focusedElement(for processIdentifier: Int) throws -> AXUIElement {
        let appElement = AXUIElementCreateApplication(pid_t(processIdentifier))
        var focusedElementRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )

        guard result == .success,
              let focusedElementRef,
              CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID()
        else {
            throw CursorContextError.focusedElementUnavailable
        }

        return unsafeDowncast(focusedElementRef, to: AXUIElement.self)
    }

    private func selectedRange(from element: AXUIElement) -> CFRange? {
        var selectedRangeRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeRef
        )

        guard result == .success,
              let selectedRangeRef,
              CFGetTypeID(selectedRangeRef) == AXValueGetTypeID()
        else {
            return nil
        }

        let value = unsafeDowncast(selectedRangeRef, to: AXValue.self)
        guard AXValueGetType(value) == .cfRange else { return nil }

        var range = CFRange()
        guard AXValueGetValue(value, .cfRange, &range) else { return nil }
        return range
    }

    private func documentLength(from element: AXUIElement) -> Int? {
        if let value = integerAttribute(kAXNumberOfCharactersAttribute as CFString, from: element) {
            return value
        }

        if let text = stringAttribute(kAXValueAttribute as CFString, from: element) {
            return text.count
        }

        return nil
    }

    private func character(at location: Int, in element: AXUIElement) -> Character? {
        guard location >= 0 else { return nil }

        var range = CFRange(location: location, length: 1)
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }

        var attributedTextRef: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXAttributedStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &attributedTextRef
        )

        guard result == .success else { return nil }

        let attributedText = attributedTextRef as? NSAttributedString
        return attributedText?.string.first
    }

    private func integerAttribute(_ attribute: CFString, from element: AXUIElement) -> Int? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard result == .success, let valueRef else { return nil }
        return (valueRef as? NSNumber)?.intValue
    }

    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard result == .success else { return nil }
        return valueRef as? String
    }

    private enum CursorContextError: Error {
        case focusedElementUnavailable
    }
}

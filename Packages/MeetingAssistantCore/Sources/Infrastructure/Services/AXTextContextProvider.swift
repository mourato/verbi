import AppKit
@preconcurrency import ApplicationServices
import Foundation
import MeetingAssistantCoreDomain

@MainActor
public final class AXTextContextProvider: TextContextProvider {
    private let textMarkerRangeAttribute: CFString = "AXTextMarkerRange" as CFString
    private let activeAppProvider: ActiveAppContextProvider
    private let exclusionPolicyProvider: () -> TextContextExclusionPolicy
    private let markdownConverter: RichTextMarkdownConverter
    private let customExcludedBundleIDsProvider: () -> [String]
    private let cache: TextContextCache
    private let failureTracker: TextContextFailureTracker

    public init(
        activeAppProvider: ActiveAppContextProvider = NSWorkspaceActiveAppContextProvider(),
        exclusionPolicyProvider: @escaping () -> TextContextExclusionPolicy = { TextContextExclusionPolicy() },
        markdownConverter: RichTextMarkdownConverter = RichTextMarkdownConverter(),
        customExcludedBundleIDsProvider: @escaping () -> [String] = { [] },
        cache: TextContextCache = TextContextCache(),
        failureTracker: TextContextFailureTracker = TextContextFailureTracker(),
    ) {
        self.activeAppProvider = activeAppProvider
        self.exclusionPolicyProvider = exclusionPolicyProvider
        self.markdownConverter = markdownConverter
        self.customExcludedBundleIDsProvider = customExcludedBundleIDsProvider
        self.cache = cache
        self.failureTracker = failureTracker
    }

    public func fetchTextContext() async throws -> TextContextSnapshot {
        guard let appContext = try await activeAppProvider.fetchActiveAppContext() else {
            throw ContextAcquisitionError.noActiveApp
        }

        let customExcludedBundleIDs = customExcludedBundleIDsProvider()
        let exclusionPolicy = exclusionPolicyProvider()

        if exclusionPolicy.isExcluded(
            bundleIdentifier: appContext.bundleIdentifier,
            customExcludedBundleIDs: customExcludedBundleIDs,
        ) {
            recordFailure(appContext: appContext, reason: .excludedApp)
            throw ContextAcquisitionError.excludedApp
        }

        guard AccessibilityPermissionService.isTrusted() else {
            recordFailure(appContext: appContext, reason: .permissionDenied)
            throw ContextAcquisitionError.permissionDenied
        }

        do {
            let focusedElement = try focusedElement(for: appContext.processIdentifier)
            let cacheKey = makeCacheKey(appContext: appContext, focusedElement: focusedElement)

            if let cached = cache.value(for: cacheKey) {
                return cached
            }

            if let fullAttributed = readTextMarkerRangeText(from: focusedElement) {
                let text = formattedText(from: fullAttributed)
                let snapshot = TextContextSnapshot(
                    text: text,
                    source: .accessibility,
                    appContext: appContext,
                )
                cache.insert(snapshot, for: cacheKey)
                return snapshot
            }

            if let visibleAttributed = readVisibleText(from: focusedElement) {
                let text = formattedText(from: visibleAttributed)
                let snapshot = TextContextSnapshot(
                    text: text,
                    source: .visibleOnly,
                    appContext: appContext,
                )
                cache.insert(snapshot, for: cacheKey)
                return snapshot
            }

            let error = ContextAcquisitionError.accessibilityUnsupported
            recordFailure(appContext: appContext, reason: error)
            throw error
        } catch let error as ContextAcquisitionError {
            recordFailure(appContext: appContext, reason: error)
            throw error
        } catch {
            let wrapped = ContextAcquisitionError.providerFailed(error.localizedDescription)
            recordFailure(appContext: appContext, reason: wrapped)
            throw wrapped
        }
    }

    public func fetchSelectedTextContext() async throws -> TextContextSnapshot? {
        guard let appContext = try await activeAppProvider.fetchActiveAppContext() else {
            throw ContextAcquisitionError.noActiveApp
        }

        let customExcludedBundleIDs = customExcludedBundleIDsProvider()
        let exclusionPolicy = exclusionPolicyProvider()
        if exclusionPolicy.isExcluded(
            bundleIdentifier: appContext.bundleIdentifier,
            customExcludedBundleIDs: customExcludedBundleIDs,
        ) {
            recordFailure(appContext: appContext, reason: .excludedApp)
            throw ContextAcquisitionError.excludedApp
        }

        guard AccessibilityPermissionService.isTrusted() else {
            recordFailure(appContext: appContext, reason: .permissionDenied)
            throw ContextAcquisitionError.permissionDenied
        }

        do {
            let focusedElement = try focusedElement(for: appContext.processIdentifier)
            guard let selectedText = readAXStringAttribute(
                focusedElement,
                attribute: kAXSelectedTextAttribute as String,
            )?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !selectedText.isEmpty
            else {
                return nil
            }

            return TextContextSnapshot(
                text: normalizeLineBreaks(selectedText),
                source: .selectedText,
                appContext: appContext,
            )
        } catch let error as ContextAcquisitionError {
            recordFailure(appContext: appContext, reason: error)
            throw error
        } catch {
            let wrapped = ContextAcquisitionError.providerFailed(error.localizedDescription)
            recordFailure(appContext: appContext, reason: wrapped)
            throw wrapped
        }
    }

    private func focusedElement(for processIdentifier: Int) throws -> AXUIElement {
        let appElement = AXUIElementCreateApplication(pid_t(processIdentifier))
        applyMessagingTimeout(appElement)
        var focusedElementRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef,
        )

        guard result == .success else {
            if result == .attributeUnsupported {
                throw ContextAcquisitionError.accessibilityUnsupported
            }
            throw ContextAcquisitionError.noFocusedElement
        }

        guard let focusedElementRef,
              CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID()
        else {
            throw ContextAcquisitionError.accessibilityUnsupported
        }

        let focused = unsafeDowncast(focusedElementRef, to: AXUIElement.self)
        applyMessagingTimeout(focused)
        return focused
    }

    private func applyMessagingTimeout(_ element: AXUIElement, seconds: Float = 1.5) {
        // Bound hung AX IPC so MainActor callers can recover instead of freezing forever.
        AXUIElementSetMessagingTimeout(element, seconds)
    }

    private func readTextMarkerRangeText(from element: AXUIElement) -> NSAttributedString? {
        applyMessagingTimeout(element)
        var markerRangeRef: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            element,
            textMarkerRangeAttribute,
            &markerRangeRef,
        )

        guard rangeResult == .success, let markerRangeRef else { return nil }

        var attributedTextRef: CFTypeRef?
        let paramResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXAttributedStringForRangeParameterizedAttribute as CFString,
            markerRangeRef,
            &attributedTextRef,
        )

        guard paramResult == .success else { return nil }
        return attributedTextRef as? NSAttributedString
    }

    private func readVisibleText(from element: AXUIElement) -> NSAttributedString? {
        applyMessagingTimeout(element)
        var visibleRangeRef: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            element,
            kAXVisibleCharacterRangeAttribute as CFString,
            &visibleRangeRef,
        )

        guard rangeResult == .success, let visibleRangeRef else { return nil }

        var attributedTextRef: CFTypeRef?
        let paramResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXAttributedStringForRangeParameterizedAttribute as CFString,
            visibleRangeRef,
            &attributedTextRef,
        )

        guard paramResult == .success else { return nil }
        return attributedTextRef as? NSAttributedString
    }

    private func formattedText(from attributedText: NSAttributedString) -> String {
        let converted = markdownConverter.convertIfRichText(attributedText)
        let rawText = converted ?? attributedText.string
        return normalizeLineBreaks(rawText)
    }

    private func makeCacheKey(appContext: ActiveAppContext, focusedElement: AXUIElement) -> String {
        let role = readAXStringAttribute(focusedElement, attribute: kAXRoleAttribute as String) ?? "unknown"
        let subrole = readAXStringAttribute(focusedElement, attribute: kAXSubroleAttribute as String) ?? "unknown"
        let identifier = readAXStringAttribute(focusedElement, attribute: kAXIdentifierAttribute as String) ?? ""
        let title = readAXStringAttribute(focusedElement, attribute: kAXTitleAttribute as String) ?? ""
        let description = readAXStringAttribute(focusedElement, attribute: kAXDescriptionAttribute as String) ?? ""

        return [
            appContext.bundleIdentifier.lowercased(),
            String(appContext.processIdentifier),
            role,
            subrole,
            identifier,
            title,
            description,
        ].joined(separator: "|")
    }

    private func readAXStringAttribute(_ element: AXUIElement, attribute: String) -> String? {
        applyMessagingTimeout(element)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private func recordFailure(appContext: ActiveAppContext, reason: ContextAcquisitionError) {
        let sanitized = sanitizedReason(reason)
        failureTracker.recordFailure(bundleIdentifier: appContext.bundleIdentifier, reason: sanitized)
        TextContextLogger.logFailure(bundleIdentifier: appContext.bundleIdentifier, reason: sanitized)
    }

    private func sanitizedReason(_ reason: ContextAcquisitionError) -> ContextAcquisitionError {
        switch reason {
        case .providerFailed:
            .providerFailed("redacted")
        default:
            reason
        }
    }

    private func normalizeLineBreaks(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

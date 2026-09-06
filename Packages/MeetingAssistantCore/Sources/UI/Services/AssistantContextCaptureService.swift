import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

public struct PostProcessingContextCaptureResult: Sendable {
    public let context: String?
    public let items: [TranscriptionContextItem]
    public let didTimeout: Bool

    public init(context: String?, items: [TranscriptionContextItem], didTimeout: Bool) {
        self.context = context
        self.items = items
        self.didTimeout = didTimeout
    }
}

@MainActor
public final class AssistantContextCaptureService {
    private let contextAwarenessService: any ContextAwarenessServiceProtocol
    private let textContextProvider: any TextContextProvider
    private let textContextGuardrails: TextContextGuardrails
    private let textContextPolicy: TextContextPolicy
    private let isAccessibilityTrusted: () -> Bool
    private let requestAccessibilityPermission: () -> Void

    public init(
        contextAwarenessService: any ContextAwarenessServiceProtocol,
        textContextProvider: any TextContextProvider,
        textContextGuardrails: TextContextGuardrails,
        textContextPolicy: TextContextPolicy,
        isAccessibilityTrusted: @escaping () -> Bool = { AccessibilityPermissionService.isTrusted() },
        requestAccessibilityPermission: @escaping () -> Void = { AccessibilityPermissionService.requestPermission() },
    ) {
        self.contextAwarenessService = contextAwarenessService
        self.textContextProvider = textContextProvider
        self.textContextGuardrails = textContextGuardrails
        self.textContextPolicy = textContextPolicy
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.requestAccessibilityPermission = requestAccessibilityPermission
    }

    public func capturePostProcessingContext(
        for meeting: Meeting,
        settings: AppSettingsStore,
        activeTabURL: String?,
        calendarContext: String?,
        isDictationMode: Bool,
        contextSourcePolicy: DictationContextSourcePolicy? = nil,
        includeWindowOCR: Bool? = nil,
    ) async -> (context: String?, items: [TranscriptionContextItem]) {
        let options = effectiveCaptureOptions(
            settings: settings,
            contextSourcePolicy: contextSourcePolicy,
            includeWindowOCR: includeWindowOCR,
        )

        guard options.hasEnabledContextSources else {
            AppLogger.debug(
                "Context sources disabled, skipping context capture",
                category: .recordingManager,
                extra: ["reasonCode": "context.sources_disabled"],
            )

            guard let activeTabURL else {
                return (nil, [])
            }

            return (
                nil,
                [TranscriptionContextItem(source: .activeTabURL, text: activeTabURL)],
            )
        }

        let snapshot = await contextAwarenessService.captureSnapshot(
            options: .init(
                includeActiveApp: true,
                includeClipboard: options.includeClipboard,
                includeWindowOCR: options.includeWindowOCR,
                includeAccessibilityText: options.includeAccessibilityText,
                protectSensitiveApps: true,
                redactSensitiveData: options.redactSensitiveData,
                excludedBundleIDs: settings.contextAwarenessExcludedBundleIDs,
            ),
        )

        var context = contextAwarenessService.makePostProcessingContext(from: snapshot)
        var items = makeContextItems(from: snapshot)

        if let activeTabURL {
            appendActiveTabURLContext(activeTabURL, to: &context, items: &items)
        }

        if let calendarContext {
            appendCalendarContext(calendarContext, to: &context, items: &items)
        }

        await appendFocusedTextContextIfNeeded(
            snapshot: snapshot,
            isDictationMode: isDictationMode,
            options: options,
            context: &context,
            items: &items,
        )

        logContextCaptureSummary(snapshot: snapshot, items: items, settings: settings)
        return (context, items)
    }

    public func captureSelectedTextAtDictationStart(
        contextSourcePolicy: DictationContextSourcePolicy?,
        timeoutNanoseconds: UInt64 = 1_500_000_000,
    ) async -> (context: String?, item: TranscriptionContextItem?) {
        guard contextSourcePolicy?.includeSelectedTextAtStart == true else {
            return (nil, nil)
        }

        guard isAccessibilityTrusted() else {
            AppLogger.warning(
                "Selected text at dictation start skipped: accessibility permission not granted",
                category: .recordingManager,
                extra: ["reasonCode": "selected_text_at_start.permission_denied"],
            )
            return (nil, nil)
        }

        return await withTaskGroup(
            of: (context: String?, item: TranscriptionContextItem?, didTimeout: Bool).self,
            returning: (context: String?, item: TranscriptionContextItem?).self,
        ) { group in
            group.addTask {
                let capture = await self.fetchSelectedTextAtDictationStart(contextSourcePolicy: contextSourcePolicy)
                return (capture.context, capture.item, false)
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return (nil, nil, true)
            }

            let first = await group.next() ?? (nil, nil, true)
            group.cancelAll()

            if first.didTimeout {
                AppLogger.warning(
                    "Selected text at dictation start timed out",
                    category: .recordingManager,
                    extra: ["reasonCode": "selected_text_at_start.timeout"],
                )
                return (nil, nil)
            }

            return (first.context, first.item)
        }
    }

    private func fetchSelectedTextAtDictationStart(
        contextSourcePolicy: DictationContextSourcePolicy?,
    ) async -> (context: String?, item: TranscriptionContextItem?) {
        do {
            guard let snapshot = try await textContextProvider.fetchSelectedTextContext() else {
                return (nil, nil)
            }

            let guarded = textContextGuardrails.apply(to: snapshot.text, policy: textContextPolicy)
            var normalized = guarded.trimmingCharacters(in: .whitespacesAndNewlines)
            if contextSourcePolicy?.redactSensitiveData == true {
                normalized = ContextAwarenessPrivacy.redactSensitiveText(normalized) ?? ""
            }
            guard !normalized.isEmpty else { return (nil, nil) }

            let item = TranscriptionContextItem(source: .selectedTextAtStart, text: normalized)
            let context = """
            CONTEXT_METADATA
            <SELECTED_TEXT_AT_START>
            (normalized)
            </SELECTED_TEXT_AT_START>
            """
            return (context, item)
        } catch {
            AppLogger.warning(
                "Selected text at dictation start failed",
                category: .recordingManager,
                extra: [
                    "reasonCode": "selected_text_at_start.provider_failed",
                    "error": error.localizedDescription,
                ],
            )
            return (nil, nil)
        }
    }

    // Public compatibility surface; keep the existing call shape for external clients.
    // swiftlint:disable:next function_parameter_count
    public func capturePostProcessingContextWithTimeout(
        for meeting: Meeting,
        settings: AppSettingsStore,
        activeTabURL: String?,
        calendarContext: String?,
        isDictationMode: Bool,
        contextSourcePolicy: DictationContextSourcePolicy? = nil,
        includeWindowOCR: Bool? = nil,
        timeoutNanoseconds: UInt64,
    ) async -> PostProcessingContextCaptureResult {
        await capturePostProcessingContextWithTimeout(
            PostProcessingContextCaptureRequest(
                meeting: meeting,
                settings: settings,
                activeTabURL: activeTabURL,
                calendarContext: calendarContext,
                isDictationMode: isDictationMode,
                contextSourcePolicy: contextSourcePolicy,
                includeWindowOCR: includeWindowOCR,
            ),
            timeoutNanoseconds: timeoutNanoseconds,
        )
    }

    private func capturePostProcessingContextWithTimeout(
        _ request: PostProcessingContextCaptureRequest,
        timeoutNanoseconds: UInt64,
    ) async -> PostProcessingContextCaptureResult {
        await withTaskGroup(
            of: PostProcessingContextCaptureResult.self,
            returning: PostProcessingContextCaptureResult.self,
        ) { group in
            group.addTask {
                let capture = await self.capturePostProcessingContext(
                    for: request.meeting,
                    settings: request.settings,
                    activeTabURL: request.activeTabURL,
                    calendarContext: request.calendarContext,
                    isDictationMode: request.isDictationMode,
                    contextSourcePolicy: request.contextSourcePolicy,
                    includeWindowOCR: request.includeWindowOCR,
                )
                return PostProcessingContextCaptureResult(
                    context: capture.context,
                    items: capture.items,
                    didTimeout: false,
                )
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return PostProcessingContextCaptureResult(context: nil, items: [], didTimeout: true)
            }

            let firstResult = await group.next() ?? PostProcessingContextCaptureResult(
                context: nil,
                items: [],
                didTimeout: true,
            )
            group.cancelAll()
            return firstResult
        }
    }

    public func makeContextItems(from snapshot: ContextAwarenessSnapshot) -> [TranscriptionContextItem] {
        var items: [TranscriptionContextItem] = []

        if let activeAppName = snapshot.activeAppName {
            items.append(TranscriptionContextItem(source: .activeApp, text: activeAppName))
        }

        if let activeWindowTitle = snapshot.activeWindowTitle {
            items.append(TranscriptionContextItem(source: .windowTitle, text: activeWindowTitle))
        }

        if let accessibilityText = snapshot.activeAccessibilityText {
            items.append(TranscriptionContextItem(source: .accessibilityText, text: accessibilityText))
        }

        if let clipboardText = snapshot.clipboardText {
            items.append(TranscriptionContextItem(source: .clipboard, text: clipboardText))
        }

        if let ocrText = snapshot.activeWindowOCRText {
            items.append(TranscriptionContextItem(source: .windowOCR, text: ocrText))
        }

        return items
    }

    private func captureFocusedTextContext(redactSensitiveData: Bool) async -> String? {
        guard isAccessibilityTrusted() else {
            AppLogger.warning(
                "Focused text capture skipped: accessibility permission not granted",
                category: .recordingManager,
                extra: ["reasonCode": "focused_text.permission_denied"],
            )
            requestAccessibilityPermission()
            return nil
        }

        do {
            let snapshot = try await textContextProvider.fetchTextContext()
            let guarded = textContextGuardrails.apply(to: snapshot.text, policy: textContextPolicy)
            var normalized = guarded.trimmingCharacters(in: .whitespacesAndNewlines)

            if redactSensitiveData {
                normalized = ContextAwarenessPrivacy.redactSensitiveText(normalized) ?? ""
            }

            return normalized.isEmpty ? nil : normalized
        } catch {
            AppLogger.warning(
                "Focused text capture failed",
                category: .recordingManager,
                extra: [
                    "reasonCode": "focused_text.provider_failed",
                    "error": error.localizedDescription,
                ],
            )
            return nil
        }
    }

    private func appendFocusedTextContextIfNeeded(
        snapshot: ContextAwarenessSnapshot,
        isDictationMode: Bool,
        options: EffectiveContextCaptureOptions,
        context: inout String?,
        items: inout [TranscriptionContextItem],
    ) async {
        guard isDictationMode else { return }
        guard options.includeAccessibilityText else { return }
        guard snapshot.activeAccessibilityText == nil else { return }
        guard let focusedText = await captureFocusedTextContext(redactSensitiveData: options.redactSensitiveData) else { return }
        guard !items.contains(where: { $0.source == .focusedText && $0.text == focusedText }) else { return }

        items.append(TranscriptionContextItem(source: .focusedText, text: focusedText))
        appendContextBlock(
            tag: "FOCUSED_TEXT",
            value: focusedText,
            to: &context,
        )
    }

    private struct EffectiveContextCaptureOptions {
        let includeClipboard: Bool
        let includeWindowOCR: Bool
        let includeAccessibilityText: Bool
        let redactSensitiveData: Bool

        var hasEnabledContextSources: Bool {
            includeClipboard || includeWindowOCR || includeAccessibilityText
        }
    }

    private struct PostProcessingContextCaptureRequest {
        let meeting: Meeting
        let settings: AppSettingsStore
        let activeTabURL: String?
        let calendarContext: String?
        let isDictationMode: Bool
        let contextSourcePolicy: DictationContextSourcePolicy?
        let includeWindowOCR: Bool?
    }

    private func effectiveCaptureOptions(
        settings: AppSettingsStore,
        contextSourcePolicy: DictationContextSourcePolicy?,
        includeWindowOCR: Bool?,
    ) -> EffectiveContextCaptureOptions {
        EffectiveContextCaptureOptions(
            includeClipboard: contextSourcePolicy?.includeClipboard
                ?? settings.contextAwarenessIncludeClipboard,
            includeWindowOCR: includeWindowOCR
                ?? contextSourcePolicy?.includeWindowOCR
                ?? settings.contextAwarenessIncludeWindowOCR,
            includeAccessibilityText: contextSourcePolicy?.includeAccessibilityText
                ?? settings.contextAwarenessIncludeAccessibilityText,
            redactSensitiveData: contextSourcePolicy?.redactSensitiveData ?? settings.contextAwarenessRedactSensitiveData,
        )
    }

    private func appendActiveTabURLContext(
        _ activeTabURL: String,
        to context: inout String?,
        items: inout [TranscriptionContextItem],
    ) {
        items.append(TranscriptionContextItem(source: .activeTabURL, text: activeTabURL))
        appendContextBlock(tag: "ACTIVE_TAB_URL", value: activeTabURL, to: &context)
    }

    private func appendCalendarContext(
        _ calendarContext: String,
        to context: inout String?,
        items: inout [TranscriptionContextItem],
    ) {
        items.append(TranscriptionContextItem(source: .calendarEvent, text: calendarContext))

        appendContextBlock(tag: "CALENDAR_CONTEXT", value: calendarContext, to: &context)
    }

    private func appendContextBlock(tag: String, value: String, to context: inout String?) {
        let block = "<\(tag)>\n\(value)\n</\(tag)>"
        if let existingContext = context,
           !existingContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            context = "\(existingContext)\n\(block)"
        } else {
            context = """
            CONTEXT_METADATA
            \(block)
            """
        }
    }

    private func logContextCaptureSummary(
        snapshot: ContextAwarenessSnapshot,
        items: [TranscriptionContextItem],
        settings: AppSettingsStore,
    ) {
        if settings.contextAwarenessIncludeWindowOCR, snapshot.activeWindowOCRText == nil {
            AppLogger.debug(
                "Context capture finished without OCR text",
                category: .recordingManager,
                extra: ["reasonCode": "context.ocr_missing"],
            )
        }

        if items.isEmpty {
            AppLogger.info(
                "Context capture finished with no context items",
                category: .recordingManager,
                extra: ["reasonCode": "context.empty"],
            )
            return
        }

        AppLogger.debug(
            "Context capture finished",
            category: .recordingManager,
            extra: [
                "reasonCode": "context.captured",
                "itemCount": items.count,
                "sources": items.map(\.source.rawValue).joined(separator: ","),
            ],
        )
    }
}

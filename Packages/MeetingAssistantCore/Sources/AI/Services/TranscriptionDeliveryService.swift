import AppKit
import ApplicationServices
import Carbon
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

@MainActor
public struct TranscriptionDeliveryService {
    public static var cursorTextContextProvider: any CursorTextContextProvider = AXCursorTextContextProvider()

    public static func deliver(
        transcription: Transcription,
        recordingSource: RecordingSource? = nil,
        textPolicy: DictationTextHandlingPolicy? = nil,
        settings: DeliverySettingsConfig = AppSettingsStore.shared,
        pasteboard: PasteboardServiceProtocol = PasteboardService.shared
    ) {
        let shouldAutoCopy: Bool
        let shouldAutoPaste: Bool

        if isDictationDelivery(transcription: transcription, recordingSource: recordingSource) {
            shouldAutoCopy = textPolicy?.autoCopyToClipboard ?? settings.autoCopyTranscriptionToClipboard
            shouldAutoPaste = textPolicy?.autoPasteToActiveApp ?? settings.autoPasteTranscriptionToActiveApp
        } else {
            shouldAutoCopy = false
            shouldAutoPaste = false
        }

        guard shouldAutoCopy || shouldAutoPaste else { return }

        let baseText = transcriptionDeliveryText(from: transcription)
        let paragraphFormattedText: String = if shouldApplySmartParagraphs(
            transcription: transcription,
            shouldDeliver: shouldAutoCopy || shouldAutoPaste,
            settings: settings,
            textPolicy: textPolicy
        ) {
            SmartParagraphFormatter.format(dictatedText: baseText)
        } else {
            baseText
        }

        let textToCopy: String
        if shouldApplySmartSpacing(
            transcription: transcription,
            shouldDeliver: shouldAutoCopy || shouldAutoPaste,
            settings: settings,
            textPolicy: textPolicy
        ) {
            let cursorContext = cursorTextContextProvider.fetchCursorTextContext()
            textToCopy = SmartSpacingFormatter.format(dictatedText: paragraphFormattedText, cursorContext: cursorContext)
        } else {
            textToCopy = paragraphFormattedText
        }

        pasteboard.clearContents()
        pasteboard.setString(textToCopy, forType: .string)

        if shouldAutoPaste {
            pasteboard.setString(textToCopy, forType: .string) // Ensure it's ready for pasting
            pasteTranscriptionIntoActiveApp()
        }
    }

    private static func isDictationDelivery(transcription: Transcription, recordingSource: RecordingSource?) -> Bool {
        if let recordingSource {
            return recordingSource == .microphone && transcription.capturePurpose == .dictation
        }

        return transcription.capturePurpose == .dictation
    }

    private static func transcriptionDeliveryText(from transcription: Transcription) -> String {
        let contextMetadata: String? = {
            let normalizedItems = transcription.contextItems
                .map(\.text)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard !normalizedItems.isEmpty else { return nil }
            return normalizedItems.joined(separator: "\n")
        }()

        let sanitized = TranscriptionOutputSanitizer.sanitize(
            processedContent: transcription.processedContent,
            contextMetadata: contextMetadata
        )
        if let candidate = sanitized.text, !candidate.isEmpty {
            return candidate
        }
        return transcription.rawText
    }

    private static func shouldApplySmartSpacing(
        transcription: Transcription,
        shouldDeliver: Bool,
        settings: DeliverySettingsConfig,
        textPolicy: DictationTextHandlingPolicy?
    ) -> Bool {
        shouldDeliver
            && (textPolicy?.smartSpacingAndCapitalization ?? settings.smartSpacingAndCapitalizationEnabled)
            && transcription.capturePurpose == .dictation
    }

    private static func shouldApplySmartParagraphs(
        transcription: Transcription,
        shouldDeliver: Bool,
        settings: DeliverySettingsConfig,
        textPolicy: DictationTextHandlingPolicy?
    ) -> Bool {
        shouldDeliver
            && (textPolicy?.smartParagraphs ?? settings.smartParagraphsEnabled)
            && transcription.capturePurpose == .dictation
    }

    private static func pasteTranscriptionIntoActiveApp() {
        guard AccessibilityPermissionService.isTrusted() else {
            AppLogger.error(
                "Accessibility permission missing for auto-paste",
                category: .recordingManager
            )
            return
        }

        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_V),
            keyDown: true
        )
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_V),
            keyDown: false
        )
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

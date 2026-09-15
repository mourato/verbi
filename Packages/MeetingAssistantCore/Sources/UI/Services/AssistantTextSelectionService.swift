import AppKit
@preconcurrency import ApplicationServices
import Carbon
import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

@MainActor
public final class AssistantTextSelectionService {
    /// Represents a deep copy of pasteboard content at a specific point in time.
    /// This stores actual data values rather than references to NSPasteboardItem,
    /// which become invalid after pasteboard changes.
    struct PasteboardSnapshot {
        /// Each item contains a dictionary mapping UTType identifiers to their data.
        let itemsData: [[(NSPasteboard.PasteboardType, Data)]]
        let changeCount: Int

        /// Creates a snapshot by deep-copying all data from the current pasteboard items.
        static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
            var itemsData: [[(NSPasteboard.PasteboardType, Data)]] = []

            for item in pasteboard.pasteboardItems ?? [] {
                var itemData: [(NSPasteboard.PasteboardType, Data)] = []
                for type in item.types {
                    if let data = item.data(forType: type) {
                        itemData.append((type, data))
                    }
                }
                if !itemData.isEmpty {
                    itemsData.append(itemData)
                }
            }

            return PasteboardSnapshot(itemsData: itemsData, changeCount: pasteboard.changeCount)
        }

        var isEmpty: Bool {
            itemsData.isEmpty
        }
    }

    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func captureSelectedText() async throws -> (text: String, snapshot: PasteboardSnapshot) {
        guard hasAccessibilityPermission() else {
            throw AssistantVoiceCommandError.accessibilityPermissionRequired
        }

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        simulateCopy()

        let didChange = await waitForPasteboardChange(from: snapshot.changeCount)
        guard didChange else {
            throw AssistantVoiceCommandError.noSelectionFound
        }

        guard let selectedText = pasteboard.string(forType: .string),
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw AssistantVoiceCommandError.noSelectionFound
        }

        return (selectedText, snapshot)
    }

    func replaceSelectedText(with text: String, restoring snapshot: PasteboardSnapshot) async throws {
        guard hasAccessibilityPermission() else {
            throw AssistantVoiceCommandError.accessibilityPermissionRequired
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let changeCountAfterWrite = pasteboard.changeCount

        simulatePaste()
        try? await Task.sleep(nanoseconds: 120_000_000)

        if pasteboard.changeCount == changeCountAfterWrite {
            restorePasteboard(snapshot)
        }
    }

    func restorePasteboard(_ snapshot: PasteboardSnapshot) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }

        // Recreate fresh NSPasteboardItem objects from the captured data
        var newItems: [NSPasteboardItem] = []
        for itemData in snapshot.itemsData {
            let newItem = NSPasteboardItem()
            for (type, data) in itemData {
                newItem.setData(data, forType: type)
            }
            newItems.append(newItem)
        }

        if !newItems.isEmpty {
            pasteboard.writeObjects(newItems)
        }
    }

    private func waitForPasteboardChange(from changeCount: Int) async -> Bool {
        let maxAttempts = 10
        for _ in 0 ..< maxAttempts {
            if pasteboard.changeCount != changeCount {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    private func hasAccessibilityPermission() -> Bool {
        if AccessibilityPermissionService.isTrusted() {
            return true
        }

        AccessibilityPermissionService.requestPermission()
        return false
    }

    private func simulateCopy() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_C),
            keyDown: true
        )
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_C),
            keyDown: false
        )
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func simulatePaste() {
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

import AppKit
import MarkdownEngine
import MeetingAssistantCoreCommon
import SwiftUI

struct MeetingNotesMarkdownEditor: View {
    private static let toolbarControlWidth: CGFloat = 16
    private static let toolbarControlHeight: CGFloat = 16

    @Binding var content: MeetingNotesContent
    @StateObject private var textViewBridge = MeetingNotesMarkdownTextViewBridge()
    @State private var isShowingLinkEditor = false
    @State private var linkEditorDraft = MeetingNotesMarkdownLinkDraft.empty

    let documentId: String

    init(
        content: Binding<MeetingNotesContent>,
        documentId: String = "meeting-notes",
    ) {
        _content = content
        self.documentId = documentId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            toolbar
            shortcutsHint
            editor
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(MeetingNotesMarkdownKeyboardHandler(
            onBold: { NotificationCenter.default.post(name: .meetingNotesApplyBold, object: nil) },
            onItalic: { NotificationCenter.default.post(name: .meetingNotesApplyItalic, object: nil) },
            onLink: { NotificationCenter.default.post(name: .meetingNotesApplyLink, object: nil) },
        ))
        .sheet(isPresented: $isShowingLinkEditor) {
            linkEditorSheet
        }
        .onReceive(NotificationCenter.default.publisher(for: .meetingNotesApplyLink)) { _ in
            prepareLinkEditor()
        }
    }

    private var shortcutsHint: some View {
        Text("meeting_notes.rich_text.shortcuts.cheatsheet".localized)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            toolbarButton(
                title: "meeting_notes.rich_text.toolbar.bold".localized,
                systemImage: "bold",
            ) {
                NotificationCenter.default.post(name: .meetingNotesApplyBold, object: nil)
            }

            toolbarButton(
                title: "meeting_notes.rich_text.toolbar.italic".localized,
                systemImage: "italic",
            ) {
                NotificationCenter.default.post(name: .meetingNotesApplyItalic, object: nil)
            }

            toolbarButton(
                title: "meeting_notes.rich_text.toolbar.link".localized,
                systemImage: "link",
            ) {
                prepareLinkEditor()
            }

            Spacer(minLength: 0)
        }
    }

    private var editor: some View {
        let editorFont = resolvedEditorFont()

        return NativeTextViewWrapper(
            text: markdownBinding,
            configuration: configuration,
            fontName: editorFont.fontName,
            fontSize: editorFont.pointSize,
            documentId: documentId,
        )
        .background(MeetingNotesMarkdownTextViewIntrospector(bridge: textViewBridge))
    }

    private var linkEditorSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("meeting_notes.rich_text.link_sheet.title".localized)
                .font(.headline)

            TextField("meeting_notes.rich_text.link_sheet.label_placeholder".localized, text: $linkEditorDraft.label)
                .textFieldStyle(.roundedBorder)

            TextField("meeting_notes.rich_text.link_sheet.placeholder".localized, text: $linkEditorDraft.url)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    applyLinkAndDismiss()
                }

            HStack(spacing: 8) {
                Spacer()

                Button("common.cancel".localized) {
                    isShowingLinkEditor = false
                }
                .keyboardShortcut(.cancelAction)

                Button("meeting_notes.rich_text.link_sheet.apply".localized) {
                    applyLinkAndDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    private var markdownBinding: Binding<String> {
        Binding(
            get: { content.plainText },
            set: { newValue in
                content = MeetingNotesContent(plainText: newValue)
            },
        )
    }

    private var configuration: MarkdownEditorConfiguration {
        var configuration = MarkdownEditorConfiguration.default
        configuration.services = MarkdownEditorServices(
            bus: MarkdownEditorBus(
                applyBoldRequest: .meetingNotesApplyBold,
                applyItalicRequest: .meetingNotesApplyItalic,
            ),
        )
        return configuration
    }

    private func resolvedEditorFont() -> NSFont {
        .systemFont(ofSize: CGFloat(MeetingNotesTypographyDefaults.defaultFontSize))
    }

    private func prepareLinkEditor() {
        linkEditorDraft = MeetingNotesMarkdownLinkDraft(textView: textViewBridge.textView)
        isShowingLinkEditor = true
    }

    private func applyLinkAndDismiss() {
        guard let textView = textViewBridge.textView else {
            isShowingLinkEditor = false
            return
        }

        let trimmedURL = linkEditorDraft.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            isShowingLinkEditor = false
            return
        }

        let label = linkEditorDraft.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLabel = label.isEmpty ? trimmedURL : label
        let replacement = "[\(resolvedLabel)](\(trimmedURL))"
        let replacementRange = linkEditorDraft.replacementRange ?? textView.selectedRange()
        let selectedLabelRange = NSRange(location: replacementRange.location + 1, length: (resolvedLabel as NSString).length)

        textView.breakUndoCoalescing()
        guard textView.shouldChangeText(in: replacementRange, replacementString: replacement) else {
            return
        }

        textView.replaceCharacters(in: replacementRange, with: replacement)
        textView.didChangeText()
        textView.undoManager?.setActionName("Insert Link")
        textView.breakUndoCoalescing()
        textView.setSelectedRange(selectedLabelRange)
        isShowingLinkEditor = false
    }

    private func toolbarButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: Self.toolbarControlWidth, height: Self.toolbarControlHeight)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .help(title)
    }
}

#Preview("Meeting Notes Markdown Editor") {
    PreviewStateContainer(MeetingNotesContent(plainText: "# Notes\n\n- Review backlog\n- Share [roadmap](https://example.com)")) { content in
        MeetingNotesMarkdownEditor(content: content)
            .frame(width: 700, height: 280)
            .padding(12)
    }
}

private final class MeetingNotesMarkdownTextViewBridge: ObservableObject {
    weak var textView: NSTextView?
}

private struct MeetingNotesMarkdownTextViewIntrospector: NSViewRepresentable {
    let bridge: MeetingNotesMarkdownTextViewBridge

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            updateBridge(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            updateBridge(from: nsView)
        }
    }

    private func updateBridge(from view: NSView) {
        guard let root = view.superview else { return }
        bridge.textView = findTextView(in: root)
    }

    private func findTextView(in root: NSView) -> NSTextView? {
        if let textView = root as? NSTextView {
            return textView
        }

        for subview in root.subviews {
            if let textView = findTextView(in: subview) {
                return textView
            }
        }

        return nil
    }
}

private struct MeetingNotesMarkdownLinkDraft {
    let replacementRange: NSRange?
    var label: String
    var url: String

    static let empty = MeetingNotesMarkdownLinkDraft(replacementRange: nil, label: "", url: "https://")

    init(replacementRange: NSRange?, label: String, url: String) {
        self.replacementRange = replacementRange
        self.label = label
        self.url = url
    }

    @MainActor
    init(textView: NSTextView?) {
        guard let textView else {
            self = .empty
            return
        }

        let selectedRange = textView.selectedRange()
        let text = textView.string as NSString
        if let existingLink = Self.linkMatch(containing: selectedRange, in: text) {
            self = MeetingNotesMarkdownLinkDraft(
                replacementRange: existingLink.fullRange,
                label: existingLink.label,
                url: existingLink.url,
            )
            return
        }

        let selectedLabel = selectedRange.length > 0 ? text.substring(with: selectedRange) : ""
        self = MeetingNotesMarkdownLinkDraft(
            replacementRange: selectedRange,
            label: selectedLabel,
            url: "https://",
        )
    }

    private static func linkMatch(containing selection: NSRange, in text: NSString) -> (fullRange: NSRange, label: String, url: String)? {
        let fullRange = NSRange(location: 0, length: text.length)
        guard let regex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^\)]+)\)"#) else {
            return nil
        }

        let targetLocation = selection.length > 0 ? selection.location : max(0, selection.location - 1)
        for match in regex.matches(in: text as String, range: fullRange) {
            guard match.numberOfRanges == 3 else { continue }
            let matchRange = match.range(at: 0)
            let upperBound = NSMaxRange(matchRange)
            let selectionUpperBound = NSMaxRange(selection)
            let intersects = selection.length > 0
                ? selection.location >= matchRange.location && selectionUpperBound <= upperBound
                : targetLocation >= matchRange.location && targetLocation <= upperBound

            guard intersects else { continue }

            return (
                fullRange: matchRange,
                label: text.substring(with: match.range(at: 1)),
                url: text.substring(with: match.range(at: 2)),
            )
        }

        return nil
    }
}

private struct MeetingNotesMarkdownKeyboardHandler: NSViewRepresentable {
    let onBold: () -> Void
    let onItalic: () -> Void
    let onLink: () -> Void

    func makeNSView(context: Context) -> KeyboardHandlerHostView {
        let view = KeyboardHandlerHostView()
        view.onBold = onBold
        view.onItalic = onItalic
        view.onLink = onLink
        return view
    }

    func updateNSView(_ nsView: KeyboardHandlerHostView, context: Context) {
        nsView.onBold = onBold
        nsView.onItalic = onItalic
        nsView.onLink = onLink
    }

    static func dismantleNSView(_ nsView: KeyboardHandlerHostView, coordinator: ()) {
        nsView.detach()
    }
}

private final class KeyboardHandlerHostView: NSView {
    var onBold: (() -> Void)?
    var onItalic: (() -> Void)?
    var onLink: (() -> Void)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard window != nil else { return }
        installMonitor()
    }

    func detach() {
        removeMonitor()
        onBold = nil
        onItalic = nil
        onLink = nil
    }

    private func installMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return handleKeyEvent(event)
        }
    }

    private func removeMonitor() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
              !event.modifierFlags.contains(.option),
              !event.modifierFlags.contains(.control),
              let chars = event.charactersIgnoringModifiers?.lowercased()
        else { return event }

        switch chars {
        case "b":
            onBold?()
            return nil
        case "i":
            onItalic?()
            return nil
        case "k":
            onLink?()
            return nil
        default:
            return event
        }
    }
}

private extension Notification.Name {
    static let meetingNotesApplyBold = Notification.Name("MeetingNotesMarkdownEditor.applyBold")
    static let meetingNotesApplyItalic = Notification.Name("MeetingNotesMarkdownEditor.applyItalic")
    static let meetingNotesApplyLink = Notification.Name("MeetingNotesMarkdownEditor.applyLink")
}

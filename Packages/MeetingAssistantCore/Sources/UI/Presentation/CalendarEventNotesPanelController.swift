import AppKit
import MeetingAssistantCoreCommon
import SwiftUI

@MainActor
public final class CalendarEventNotesPanelController {
    private static let initialPanelWidth: CGFloat = 420
    private static let initialPanelHeight: CGFloat = 400
    private static let minimumPanelWidth: CGFloat = 320
    private static let minimumPanelHeight: CGFloat = 220
    private static let maximumPanelWidth: CGFloat = 700
    private static let maximumScreenHeightRatio: CGFloat = 0.9
    private static let autosaveName = "CalendarEventNotesPanel"

    private var panel: NSPanel?
    private var hostingView: NSHostingView<CalendarEventNotesPanelView>?
    private var panelDelegate: PanelDelegate?

    public init() {}

    public var isVisible: Bool {
        panel?.isVisible ?? false
    }

    public func show(
        eventIdentifier: String,
        loadContent: @escaping () -> MeetingNotesContent,
        onTextChange: @escaping (MeetingNotesContent) -> Void
    ) {
        let panel = ensurePanel()
        let maxHeight = Self.maximumPanelHeight(for: panel.screen)
        panel.maxSize = NSSize(width: Self.maximumPanelWidth, height: maxHeight)

        var frame = panel.frame
        frame.size.width = min(max(frame.size.width, Self.minimumPanelWidth), Self.maximumPanelWidth)
        frame.size.height = min(max(frame.size.height, Self.minimumPanelHeight), maxHeight)

        if let screenFrame = panel.screen?.visibleFrame {
            frame.origin.x = max(screenFrame.minX, min(frame.origin.x, screenFrame.maxX - frame.width))
            frame.origin.y = max(screenFrame.minY, min(frame.origin.y, screenFrame.maxY - frame.height))
        }
        panel.setFrame(frame, display: true)

        let rootView = CalendarEventNotesPanelView(
            content: loadContent(),
            documentId: "calendar-event-notes-\(eventIdentifier)",
            onTextChange: onTextChange
        )

        if let hostingView {
            hostingView.rootView = rootView
        } else {
            let host = NSHostingView(rootView: rootView)
            host.sizingOptions = []
            host.autoresizingMask = [.width, .height]
            panel.contentView = host
            hostingView = host
        }

        panel.level = .floating
        panel.orderFrontRegardless()
        panel.makeKey()
        NSApp.activate(ignoringOtherApps: false)
    }

    public func hide() {
        panel?.orderOut(nil)
    }

    private static func maximumPanelHeight(for screen: NSScreen?) -> CGFloat {
        guard let visibleFrame = screen?.visibleFrame else {
            return minimumPanelHeight
        }
        return max(minimumPanelHeight, floor(visibleFrame.height * maximumScreenHeightRatio))
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.initialPanelWidth, height: Self.initialPanelHeight),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces]
        panel.title = "calendar_event_notes.panel.title".localized
        panel.minSize = NSSize(width: Self.minimumPanelWidth, height: Self.minimumPanelHeight)
        panel.setFrameAutosaveName(Self.autosaveName)

        let delegate = PanelDelegate(onClose: { [weak self] in
            self?.hide()
        })
        panel.delegate = delegate
        panelDelegate = delegate

        if panel.frame.origin == .zero, let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(
                NSPoint(
                    x: visible.midX - Self.initialPanelWidth / 2,
                    y: visible.midY - Self.initialPanelHeight / 2
                )
            )
        }

        self.panel = panel
        return panel
    }
}

private struct CalendarEventNotesPanelView: View {
    @State private var content: MeetingNotesContent
    let documentId: String
    let onTextChange: (MeetingNotesContent) -> Void

    init(
        content: MeetingNotesContent,
        documentId: String,
        onTextChange: @escaping (MeetingNotesContent) -> Void
    ) {
        _content = State(initialValue: content)
        self.documentId = documentId
        self.onTextChange = onTextChange
    }

    var body: some View {
        ZStack {
            SettingsWindowBackground()

            VStack(alignment: .leading, spacing: 10) {
                Text("recording_indicator.meeting_notes.help".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                MeetingNotesMarkdownEditor(content: $content, documentId: documentId)
            }
            .padding(12)
        }
        .onChange(of: content) { _, newValue in
            onTextChange(newValue)
        }
    }
}

private final class PanelDelegate: NSObject, NSWindowDelegate {
    var onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_: Notification) {
        onClose()
    }
}

import AppKit
import Combine
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

@MainActor
public final class MeetingNotesPaneController {
    public enum EditorHost {
        case swiftUI
        case webKit
    }

    private enum LayoutConstants {
        static let initialWidth: CGFloat = 420
        static let initialHeight: CGFloat = 400
        static let minimumWidth: CGFloat = 320
        static let minimumHeight: CGFloat = 220
        static let maximumWidth: CGFloat = 700
        static let maximumScreenHeightRatio: CGFloat = 0.9
        static let autosaveNamePrefix = "MeetingNotesPane"
        static let saveDebounceNanoseconds: UInt64 = 500_000_000
    }

    private let recordingManager: RecordingManager
    private let settingsStore: AppSettingsStore
    private let calendarEventService: any CalendarEventServiceProtocol

    private var panel: MeetingNotesPanePanel?
    private var hostingView: NSHostingView<MeetingNotesPaneEditorView>?
    private var panelDelegate: PanePanelDelegate?
    private var currentScope: NotesScope?
    private var editorHost: EditorHost = .webKit
    private var isUserToggledOpen = false
    private var pendingSaveTask: Task<Void, Never>?
    private var pendingContent: MeetingNotesContent?
    private var cancellables = Set<AnyCancellable>()
    private var onVisibilityChanged: ((Bool) -> Void)?

    public init(
        recordingManager: RecordingManager = .shared,
        settingsStore: AppSettingsStore = .shared,
        calendarEventService: any CalendarEventServiceProtocol = CalendarEventService.shared
    ) {
        self.recordingManager = recordingManager
        self.settingsStore = settingsStore
        self.calendarEventService = calendarEventService
        bindSettings()
    }

    public var isVisible: Bool {
        panel?.isVisible ?? false
    }

    public var activeScope: NotesScope? {
        currentScope
    }

    public var isUserOpened: Bool {
        isUserToggledOpen
    }

    public func setVisibilityHandler(_ handler: @escaping (Bool) -> Void) {
        onVisibilityChanged = handler
    }

    public func toggle(scope explicitScope: NotesScope? = nil) {
        if isVisible {
            dismiss()
        } else {
            summon(scope: explicitScope)
        }
    }

    public func summon(scope explicitScope: NotesScope? = nil) {
        guard let scope = explicitScope ?? resolveDefaultScope() else { return }

        isUserToggledOpen = true
        currentScope = scope
        present(scope: scope)
        onVisibilityChanged?(true)
    }

    public func dismiss(flushPendingSave: Bool = true) {
        if flushPendingSave {
            flushPendingSaveImmediately()
        }

        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        panel?.orderOut(nil)

        if NSApp.isActive {
            NSApp.deactivate()
        }

        isUserToggledOpen = false
        currentScope = nil
        onVisibilityChanged?(false)
    }

    public func refreshIfVisible() {
        guard isVisible, let scope = currentScope else { return }
        present(scope: scope)
    }

    public func setEditorHost(_ host: EditorHost) {
        editorHost = host
        refreshIfVisible()
    }

    private func bindSettings() {
        settingsStore.$meetingNotesShowOnAllSpaces
            .combineLatest(settingsStore.$meetingNotesHideFromScreenCapture)
            .sink { [weak self] showOnAllSpaces, hideFromCapture in
                guard let self, let panel else { return }
                panel.applyCollectionBehavior(showOnAllSpaces: showOnAllSpaces)
                panel.applyScreenCaptureVisibility(hidden: hideFromCapture)
            }
            .store(in: &cancellables)
    }

    private func resolveDefaultScope() -> NotesScope? {
        NotesScopeResolver.resolve(
            context: NotesScopeResolver.Context(
                isRecordingMeeting: recordingManager.isRecording
                    && recordingManager.currentCapturePurpose == .meeting,
                currentMeetingID: recordingManager.currentMeeting?.id,
                lastEditedCalendarEventIdentifier: settingsStore.meetingNotesLastEditedCalendarEventIdentifier,
                ignoredCalendarEventIdentifiers: settingsStore.ignoredCalendarEventIdentifiers(),
                fetchUpcomingEvents: { [calendarEventService, settingsStore] in
                    try calendarEventService.fetchUpcomingEvents(
                        limit: 10,
                        now: Date(),
                        window: 30 * 60,
                        ignoredEventIdentifiers: settingsStore.ignoredCalendarEventIdentifiers()
                    )
                }
            )
        )
    }

    private func present(scope: NotesScope) {
        let panel = ensurePanel()
        applyPanelSettings(to: panel)
        positionPanelUnderPointer(panel)

        let content = recordingManager.loadNotesContent(for: scope)
        let rootView = MeetingNotesPaneEditorView(
            scope: scope,
            content: content,
            editorHost: editorHost,
            settingsStore: settingsStore,
            onContentChange: { [weak self] updated in
                self?.scheduleSave(updated, for: scope)
            },
            onContentHeightChange: { [weak self] height in
                guard let self, let panel = self.panel else { return }
                resizePanel(panel, contentHeight: height + 72)
            }
        )

        if let hostingView {
            hostingView.rootView = rootView
        } else {
            let host = NSHostingView(rootView: rootView)
            host.translatesAutoresizingMaskIntoConstraints = false
            panel.contentView = host
            hostingView = host
        }

        resizePanel(panel, contentHeight: estimatedContentHeight(for: content))

        panel.level = .floating
        panel.orderFrontRegardless()
        panel.makeKey()

        Task { @MainActor in
            panel.makeFirstResponder(hostingView)
        }
    }

    private func ensurePanel() -> MeetingNotesPanePanel {
        if let panel {
            panelDelegate?.onClose = { [weak self] in
                self?.dismiss()
            }
            return panel
        }

        let panel = MeetingNotesPanePanel(
            contentRect: NSRect(x: 0, y: 0, width: LayoutConstants.initialWidth, height: LayoutConstants.initialHeight)
        )
        panel.minSize = NSSize(width: LayoutConstants.minimumWidth, height: LayoutConstants.minimumHeight)

        let delegate = PanePanelDelegate(onClose: { [weak self] in
            self?.dismiss()
        })
        panel.delegate = delegate
        panelDelegate = delegate

        self.panel = panel
        applyPanelSettings(to: panel)
        restoreFrameIfAvailable(for: panel)
        return panel
    }

    private func applyPanelSettings(to panel: MeetingNotesPanePanel) {
        panel.applyCollectionBehavior(showOnAllSpaces: settingsStore.meetingNotesShowOnAllSpaces)
        panel.applyScreenCaptureVisibility(hidden: settingsStore.meetingNotesHideFromScreenCapture)
        let maxHeight = Self.maximumPanelHeight(for: panel.screen)
        panel.maxSize = NSSize(width: LayoutConstants.maximumWidth, height: maxHeight)
    }

    private func restoreFrameIfAvailable(for panel: MeetingNotesPanePanel) {
        let autosaveName = autosaveName(for: panel.screen)
        panel.setFrameAutosaveName(autosaveName)
        if !panel.setFrameUsingName(autosaveName) {
            positionPanelUnderPointer(panel)
        }
    }

    private func positionPanelUnderPointer(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let visibleFrame = targetScreen?.visibleFrame else { return }

        var frame = panel.frame
        frame.origin.x = mouseLocation.x - frame.width / 2
        frame.origin.y = mouseLocation.y - frame.height / 2
        frame.origin.x = max(visibleFrame.minX, min(frame.origin.x, visibleFrame.maxX - frame.width))
        frame.origin.y = max(visibleFrame.minY, min(frame.origin.y, visibleFrame.maxY - frame.height))
        panel.setFrame(frame, display: false)
    }

    private func autosaveName(for screen: NSScreen?) -> String {
        let screenID = screen?.displayUUID?.uuidString ?? "main"
        return "\(LayoutConstants.autosaveNamePrefix)-\(screenID)"
    }

    private func resizePanel(_ panel: NSPanel, contentHeight: CGFloat) {
        guard settingsStore.meetingNotesAutoSizeHeight else { return }

        let maxHeight = Self.maximumPanelHeight(for: panel.screen)
        var frame = panel.frame
        frame.size.width = min(max(frame.size.width, LayoutConstants.minimumWidth), LayoutConstants.maximumWidth)
        let targetHeight = min(max(contentHeight, LayoutConstants.minimumHeight), maxHeight)
        frame.size.height = targetHeight

        if let visibleFrame = panel.screen?.visibleFrame {
            frame.origin.y = max(visibleFrame.minY, min(frame.origin.y, visibleFrame.maxY - frame.height))
        }

        panel.setFrame(frame, display: true)
    }

    private func estimatedContentHeight(for content: MeetingNotesContent) -> CGFloat {
        let lineCount = max(1, content.plainText.components(separatedBy: .newlines).count)
        let lineHeight: CGFloat = 20
        let chromePadding: CGFloat = 72
        return min(
            CGFloat(lineCount) * lineHeight + chromePadding,
            Self.maximumPanelHeight(for: panel?.screen)
        )
    }

    private func scheduleSave(_ content: MeetingNotesContent, for scope: NotesScope) {
        pendingContent = content
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: LayoutConstants.saveDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            self?.flushPendingSave(for: scope)
        }
    }

    private func flushPendingSave(for scope: NotesScope) {
        guard let pendingContent else { return }
        persist(pendingContent, for: scope)
        self.pendingContent = nil
    }

    private func flushPendingSaveImmediately() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        guard let scope = currentScope else { return }
        if let pendingContent {
            persist(pendingContent, for: scope)
            self.pendingContent = nil
        }
    }

    private func persist(_ content: MeetingNotesContent, for scope: NotesScope) {
        switch scope {
        case let .calendarEvent(eventIdentifier):
            settingsStore.meetingNotesLastEditedCalendarEventIdentifier = eventIdentifier
        default:
            break
        }
        recordingManager.persistNotesContent(content, for: scope)
    }

    fileprivate static func maximumPanelHeight(for screen: NSScreen?) -> CGFloat {
        guard let visibleFrame = screen?.visibleFrame else {
            return LayoutConstants.minimumHeight
        }
        return max(LayoutConstants.minimumHeight, floor(visibleFrame.height * LayoutConstants.maximumScreenHeightRatio))
    }
}

private final class PanePanelDelegate: NSObject, NSWindowDelegate {
    var onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_: Notification) {
        onClose()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let panel = window as? MeetingNotesPanePanel else { return }

        let screenID = window.screen?.displayUUID?.uuidString ?? "main"
        panel.setFrameAutosaveName("MeetingNotesPane-\(screenID)")

        let maxHeight = MeetingNotesPaneController.maximumPanelHeight(for: window.screen)
        window.maxSize = NSSize(width: 700, height: maxHeight)
    }

    func windowWillResize(_ window: NSWindow, to newSize: NSSize) -> NSSize {
        NSSize(
            width: min(max(newSize.width, window.minSize.width), window.maxSize.width),
            height: min(max(newSize.height, window.minSize.height), window.maxSize.height)
        )
    }
}

private struct MeetingNotesPaneEditorView: View {
    let scope: NotesScope
    @State private var content: MeetingNotesContent
    let editorHost: MeetingNotesPaneController.EditorHost
    let settingsStore: AppSettingsStore
    let onContentChange: (MeetingNotesContent) -> Void
    let onContentHeightChange: ((CGFloat) -> Void)?

    init(
        scope: NotesScope,
        content: MeetingNotesContent,
        editorHost: MeetingNotesPaneController.EditorHost,
        settingsStore: AppSettingsStore,
        onContentChange: @escaping (MeetingNotesContent) -> Void,
        onContentHeightChange: ((CGFloat) -> Void)? = nil
    ) {
        self.scope = scope
        _content = State(initialValue: content)
        self.editorHost = editorHost
        self.settingsStore = settingsStore
        self.onContentChange = onContentChange
        self.onContentHeightChange = onContentHeightChange
    }

    var body: some View {
        ZStack {
            if settingsStore.meetingNotesTranslucentPanel {
                SettingsWindowBackground()
            } else {
                AppDesignSystem.Colors.windowBackground
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("recording_indicator.meeting_notes.help".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                editorBody
            }
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: MeetingNotesPanePanel.cornerRadius))
        .onChange(of: content) { _, newValue in
            onContentChange(newValue)
        }
    }

    @ViewBuilder
    private var editorBody: some View {
        switch editorHost {
        case .swiftUI:
            MeetingNotesMarkdownEditor(content: $content, documentId: scope.documentId)
        case .webKit:
            MeetingNotesEditorWebView(
                documentId: scope.documentId,
                content: content,
                textSize: settingsStore.meetingNotesTextSize,
                themeCSS: MeetingNotesEditorThemeResolver.css(
                    forThemeName: settingsStore.meetingNotesEditorTheme
                ),
                onContentChange: { updated in
                    content = updated
                },
                onContentHeightChange: { height in
                    onContentHeightChange?(height)
                }
            )
        }
    }
}

private extension NSScreen {
    var displayUUID: UUID? {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return UUID(uuidString: String(format: "%032x", screenNumber.uint32Value))
    }
}

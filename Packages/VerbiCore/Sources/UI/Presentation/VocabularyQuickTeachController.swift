import AppKit
import SwiftUI
import VerbiCoreCommon

/// Presents the quick correction editor from the menu bar, a global shortcut,
/// or a dictation result. The panel activates only while it is open and returns
/// focus to the app the user came from when it closes.
@MainActor
public final class VocabularyQuickTeachController: NSObject, NSWindowDelegate {
    public static let shared = VocabularyQuickTeachController()

    private enum Layout {
        static let width: CGFloat = 560
        static let height: CGFloat = 470
    }

    private var panel: NSPanel?
    private var previousApp: NSRunningApplication?

    public var isVisible: Bool {
        panel?.isVisible ?? false
    }

    public func show() {
        capturePreviousAppIfNeeded()

        if let panel, panel.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let panel = makePanel()
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    public func dismiss() {
        guard let panel else {
            restorePreviousAppIfSafe()
            previousApp = nil
            return
        }

        panel.delegate = nil
        panel.orderOut(nil)
        panel.contentView = nil
        self.panel = nil
        restorePreviousAppIfSafe()
        previousApp = nil
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_: Notification) {
        dismiss()
    }

    // MARK: - Private

    private func capturePreviousAppIfNeeded() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        guard frontmost != NSRunningApplication.current else { return }
        previousApp = frontmost
    }

    private func restorePreviousAppIfSafe() {
        guard let previousApp,
              !previousApp.isTerminated,
              previousApp != NSRunningApplication.current
        else {
            return
        }

        let frontmost = NSWorkspace.shared.frontmostApplication
        guard frontmost == nil || frontmost == NSRunningApplication.current else {
            return
        }

        previousApp.activate(options: [])
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "settings.dictionary.quick_teach.title".localized
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let rootView = VocabularyQuickTeachView { [weak self] in
            self?.dismiss()
        }
        let hosting = NSHostingView(rootView: rootView)
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height)
        panel.contentView = hosting

        center(panel)
        return panel
    }

    private func center(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        let frame = panel.frame
        panel.setFrameOrigin(
            NSPoint(
                x: visibleFrame.midX - frame.width / 2,
                y: visibleFrame.midY - frame.height / 2
            )
        )
    }
}

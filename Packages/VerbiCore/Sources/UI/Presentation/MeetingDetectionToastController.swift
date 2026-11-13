import AppKit
import Foundation
import SwiftUI
import VerbiCoreDomain

/// Controller managing the floating, non-activating meeting detection toast NSPanel.
@MainActor
public final class MeetingDetectionToastController: ObservableObject {
    public static let shared = MeetingDetectionToastController()

    public private(set) var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var autoDismissTask: Task<Void, Never>?
    private var screenChangeObserver: NSObjectProtocol?
    private var appActivationObserver: NSObjectProtocol?
    private var previousApp: NSRunningApplication?
    private(set) var wasVerbiActivatedDuringEndPrompt = false

    @Published public private(set) var isVisible = false
    @Published public private(set) var currentState: MeetingDetectionToastState?

    public var onRecord: (@MainActor () -> Void)?
    public var onRecordWithoutSummary: (@MainActor () -> Void)?
    public var onStop: (@MainActor () -> Void)?
    public var onKeepRecording: (@MainActor () -> Void)?
    public var onDismiss: (@MainActor () -> Void)?

    public enum Constants {
        public static let toastWidth: CGFloat = 500
        public static let toastHeight: CGFloat = 104
        public static let topMargin: CGFloat = 12
        public static let rightMargin: CGFloat = 16
        public static let autoDismissDuration: TimeInterval = 12.0
    }

    public init() {
        setupScreenObserver()
        setupApplicationActivationObserver()
    }

    isolated deinit {
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        autoDismissTask?.cancel()
    }

    // MARK: - Public API

    public func show(
        state: MeetingDetectionToastState,
        onRecord: (@MainActor () -> Void)? = nil,
        onRecordWithoutSummary: (@MainActor () -> Void)? = nil,
        onStop: (@MainActor () -> Void)? = nil,
        onKeepRecording: (@MainActor () -> Void)? = nil,
        onDismiss: (@MainActor () -> Void)? = nil
    ) {
        let wasEndPrompt = isEndPrompt(currentState)
        let willShowEndPrompt = isEndPrompt(state)
        if willShowEndPrompt, !wasEndPrompt {
            previousApp = NSWorkspace.shared.frontmostApplication
            wasVerbiActivatedDuringEndPrompt = false
        }

        self.onRecord = onRecord
        self.onRecordWithoutSummary = onRecordWithoutSummary
        self.onStop = onStop
        self.onKeepRecording = onKeepRecording
        self.onDismiss = onDismiss

        currentState = state
        isVisible = true

        let panel = ensurePanel()
        (panel as? MeetingDetectionToastPanel)?.canBecomeKeyForEndPrompt = willShowEndPrompt
        updateContent()
        reposition(panel: panel)
        if willShowEndPrompt {
            if let promptPanel = panel as? MeetingDetectionToastPanel {
                promptPanel.onReturn = { [weak self] in self?.onStop?() }
                promptPanel.onEscape = { [weak self] in self?.onKeepRecording?() }
            }
        } else if let promptPanel = panel as? MeetingDetectionToastPanel {
            promptPanel.onReturn = nil
            promptPanel.onEscape = nil
        }

        // Non-activating presentation: never steals focus, never touches active app.
        panel.orderFrontRegardless()
        if willShowEndPrompt {
            panel.makeKey()
            announceMeetingEndPrompt(state)
        } else if wasEndPrompt {
            leaveEndPromptFocus(panel)
        }

        manageAutoDismiss(for: state)
    }

    public func update(state: MeetingDetectionToastState) {
        guard isVisible else {
            show(state: state)
            return
        }

        let wasEndPrompt = isEndPrompt(currentState)
        let willShowEndPrompt = isEndPrompt(state)
        if willShowEndPrompt, !wasEndPrompt {
            previousApp = NSWorkspace.shared.frontmostApplication
            wasVerbiActivatedDuringEndPrompt = false
        }

        currentState = state
        (panel as? MeetingDetectionToastPanel)?.canBecomeKeyForEndPrompt = willShowEndPrompt
        updateContent()
        if let panel = panel as? MeetingDetectionToastPanel {
            if willShowEndPrompt {
                panel.onReturn = { [weak self] in self?.onStop?() }
                panel.onEscape = { [weak self] in self?.onKeepRecording?() }
            } else {
                panel.onReturn = nil
                panel.onEscape = nil
            }
        }
        manageAutoDismiss(for: state)
        if willShowEndPrompt {
            panel?.makeKey()
            announceMeetingEndPrompt(state)
        } else if wasEndPrompt, let panel {
            leaveEndPromptFocus(panel)
        }
    }

    public func hide() {
        if isEndPrompt(currentState), let panel {
            leaveEndPromptFocus(panel)
        }
        autoDismissTask?.cancel()
        autoDismissTask = nil
        isVisible = false
        currentState = nil
        panel?.orderOut(nil)
    }

    public func reposition(panel: NSPanel? = nil) {
        guard let panel = panel ?? self.panel else { return }
        let screen = targetScreen()
        let visibleFrame = screen.visibleFrame
        let contentSize = CGSize(width: Constants.toastWidth, height: Constants.toastHeight)

        let originX = visibleFrame.maxX - contentSize.width - Constants.rightMargin
        let originY = visibleFrame.maxY - contentSize.height - Constants.topMargin

        panel.setFrame(NSRect(x: originX, y: originY, width: contentSize.width, height: contentSize.height), display: true)
    }

    // MARK: - Private Helpers

    public func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let panel = MeetingDetectionToastPanel(
            contentRect: NSRect(x: 0, y: 0, width: Constants.toastWidth, height: Constants.toastHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = false

        let hosting = NSHostingView(rootView: AnyView(EmptyView()))
        panel.contentView = hosting
        hostingView = hosting
        self.panel = panel

        return panel
    }

    private func updateContent() {
        guard let hostingView, let state = currentState else { return }
        let view = MeetingDetectionToastView(
            state: state,
            onRecord: { [weak self] in
                self?.onRecord?()
            },
            onRecordWithoutSummary: { [weak self] in
                self?.onRecordWithoutSummary?()
            },
            onStop: { [weak self] in
                self?.onStop?()
            },
            onKeepRecording: { [weak self] in
                self?.onKeepRecording?()
            },
            onDismiss: { [weak self] in
                self?.onDismiss?()
                self?.hide()
            }
        )
        hostingView.rootView = AnyView(view)
    }

    private func manageAutoDismiss(for state: MeetingDetectionToastState) {
        autoDismissTask?.cancel()
        autoDismissTask = nil

        if case .detected = state {
            autoDismissTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Constants.autoDismissDuration))
                guard !Task.isCancelled, let self else { return }
                if case .detected = currentState {
                    hide()
                }
            }
        }
    }

    private func announceMeetingEndPrompt(_ state: MeetingDetectionToastState) {
        guard case let .endPrompt(_, _, _, deadline) = state else { return }
        let seconds = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
        let announcement = "toast.meeting_end_prompt".localized(with: seconds)
        NSAccessibility.post(
            element: panel ?? NSApp,
            notification: .announcementRequested,
            userInfo: [
                .announcement: announcement,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    private func leaveEndPromptFocus(_ panel: NSPanel) {
        (panel as? MeetingDetectionToastPanel)?.canBecomeKeyForEndPrompt = false
        panel.resignKey()
        restorePreviousAppIfSafe()
        previousApp = nil
        wasVerbiActivatedDuringEndPrompt = false
    }

    private func restorePreviousAppIfSafe() {
        guard !wasVerbiActivatedDuringEndPrompt,
              let previousApp,
              !previousApp.isTerminated,
              previousApp != NSRunningApplication.current
        else { return }

        let frontmostApp = NSWorkspace.shared.frontmostApplication
        guard frontmostApp == nil || frontmostApp == NSRunningApplication.current else { return }
        previousApp.activate(options: [])
    }

    private func isEndPrompt(_ state: MeetingDetectionToastState?) -> Bool {
        guard let state else { return false }
        guard case .endPrompt = state else { return false }
        return true
    }

    private func targetScreen() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        if let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return mouseScreen
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    private func setupScreenObserver() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, isVisible else { return }
                reposition()
            }
        }
    }

    private func setupApplicationActivationObserver() {
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let activatedVerbi = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
                == NSRunningApplication.current
            guard activatedVerbi else { return }
            MainActor.assumeIsolated {
                guard let self, self.isEndPrompt(self.currentState) else { return }
                self.wasVerbiActivatedDuringEndPrompt = true
            }
        }
    }
}

private final class MeetingDetectionToastPanel: NSPanel {
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?
    var canBecomeKeyForEndPrompt = false

    override var canBecomeKey: Bool {
        canBecomeKeyForEndPrompt
    }

    override func cancelOperation(_: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            onReturn?()
        case 53:
            onEscape?()
        default:
            super.keyDown(with: event)
        }
    }
}

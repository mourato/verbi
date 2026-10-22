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

    @Published public private(set) var isVisible = false
    @Published public private(set) var currentState: MeetingDetectionToastState?

    public var onRecord: (@MainActor () -> Void)?
    public var onRecordWithoutSummary: (@MainActor () -> Void)?
    public var onStop: (@MainActor () -> Void)?
    public var onDismiss: (@MainActor () -> Void)?

    public enum Constants {
        public static let toastWidth: CGFloat = 380
        public static let toastHeight: CGFloat = 88
        public static let topMargin: CGFloat = 12
        public static let rightMargin: CGFloat = 16
        public static let autoDismissDuration: TimeInterval = 12.0
    }

    public init() {
        setupScreenObserver()
    }

    isolated deinit {
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        autoDismissTask?.cancel()
    }

    // MARK: - Public API

    public func show(
        state: MeetingDetectionToastState,
        onRecord: (@MainActor () -> Void)? = nil,
        onRecordWithoutSummary: (@MainActor () -> Void)? = nil,
        onStop: (@MainActor () -> Void)? = nil,
        onDismiss: (@MainActor () -> Void)? = nil
    ) {
        self.onRecord = onRecord
        self.onRecordWithoutSummary = onRecordWithoutSummary
        self.onStop = onStop
        self.onDismiss = onDismiss

        currentState = state
        isVisible = true

        let panel = ensurePanel()
        updateContent()
        reposition(panel: panel)

        // Non-activating presentation: never steals focus, never touches active app.
        panel.orderFrontRegardless()

        manageAutoDismiss(for: state)
    }

    public func update(state: MeetingDetectionToastState) {
        guard isVisible else {
            show(state: state)
            return
        }

        currentState = state
        updateContent()
        manageAutoDismiss(for: state)
    }

    public func hide() {
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

        let panel = NSPanel(
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
}

import AppKit
import SwiftUI

/// Opt-in window-level drawer. Existing detail-column drawers are unaffected.
@MainActor
struct SettingsWindowPanelBridge<PanelContent: View>: NSViewRepresentable {
    let isPresented: Bool
    let width: CGFloat
    let onDismiss: () -> Void
    let onEscape: (() -> Void)?
    @ViewBuilder let panelContent: () -> PanelContent

    func makeNSView(context _: Context) -> SettingsWindowPanelAnchor {
        SettingsWindowPanelAnchor()
    }

    func updateNSView(_ anchor: SettingsWindowPanelAnchor, context: Context) {
        anchor.host.requestedWidth = width
        anchor.host.onDismiss = onDismiss
        anchor.host.onEscape = onEscape ?? onDismiss
        // Reuse the drawer surface and motion without the detail-column titlebar inset.
        anchor.host.hostingController.rootView = AnyView(
            Color.clear
                .modifier(SettingsSidePanelModifier(
                    isPresented: isPresented,
                    width: width,
                    topContentInset: 0,
                    onDismiss: onDismiss,
                    onEscape: onEscape,
                    panelContent: panelContent
                ))
                .ignoresSafeArea()
                .environment(\.self, context.environment)
        )
        anchor.host.isPresented = isPresented
    }

    static func dismantleNSView(_ anchor: SettingsWindowPanelAnchor, coordinator _: ()) {
        anchor.host.detach()
    }
}

@MainActor
final class SettingsWindowPanelAnchor: NSView {
    let host = SettingsWindowPanelHost()

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        host.detach()
        if let window {
            host.attach(to: window)
        }
    }
}

/// A sibling above the content and titlebar containers, constrained to the
/// full-size content bounds rather than its toolbar-excluding layout guide.
@MainActor
final class SettingsWindowPanelHost: NSView {
    let hostingController = NSHostingController(rootView: AnyView(Color.clear))
    var isPresented = false {
        didSet {
            if oldValue != isPresented {
                updateModalState()
            }
        }
    }

    var requestedWidth: CGFloat = 0
    var onDismiss: () -> Void = {}
    var onEscape: () -> Void = {}
    @MainActor
    struct EventMonitoring {
        var install: (@escaping (NSEvent) -> NSEvent?) -> Any?
        var remove: (Any) -> Void

        static let local = EventMonitoring(
            install: { handler in
                NSEvent.addLocalMonitorForEvents(
                    matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown],
                    handler: handler
                )
            },
            remove: NSEvent.removeMonitor
        )
    }

    private let eventMonitoring: EventMonitoring
    private var eventMonitor: Any?
    private weak var previousResponder: NSResponder?
    private weak var underlyingContent: NSView?
    private var wasContentHidden = false

    private func updateModalState() {
        guard let window else { return }
        let hostedView = hostingController.view
        hostedView.setAccessibilityModal(isPresented)
        if isPresented {
            if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor {
                previousResponder = editor.delegate as? NSResponder
            } else {
                previousResponder = window.firstResponder
            }
            underlyingContent = window.contentView
            wasContentHidden = underlyingContent?.isAccessibilityHidden() ?? false
            underlyingContent?.setAccessibilityHidden(true)
            hostedView.layoutSubtreeIfNeeded()
            moveFocus(backward: false)
            hostedView.setAccessibilityFocused(true)
            NSAccessibility.post(element: hostedView, notification: .layoutChanged)
        } else {
            restoreUnderlyingContent()
        }
    }

    private func restoreUnderlyingContent() {
        underlyingContent?.setAccessibilityHidden(wasContentHidden)
        underlyingContent = nil
        hostingController.view.setAccessibilityModal(false)
        if let previousResponder {
            window?.makeFirstResponder(previousResponder)
        }
        previousResponder = nil
    }

    private func moveFocus(backward: Bool) {
        guard let window else { return }
        let hostedView = hostingController.view
        let current: NSView? = if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor {
            editor.delegate as? NSView
        } else {
            window.firstResponder as? NSView
        }
        let start = current.flatMap { $0.isDescendant(of: hostedView) ? $0 : nil } ?? hostedView
        var candidate = backward ? start.previousValidKeyView : start.nextValidKeyView
        var visited = Set<ObjectIdentifier>()
        while let view = candidate, visited.insert(ObjectIdentifier(view)).inserted {
            if view.isDescendant(of: hostedView), window.makeFirstResponder(view) {
                return
            }
            candidate = backward ? view.previousValidKeyView : view.nextValidKeyView
        }
        // A drawer without key views must still keep typing out of the list.
        window.makeFirstResponder(nil)
    }

    init(eventMonitoring: EventMonitoring = .local) {
        self.eventMonitoring = eventMonitoring
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let hostedView = hostingController.view
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder _: NSCoder) {
        nil
    }

    func attach(to window: NSWindow) {
        detach()
        guard let content = window.contentView, let container = content.superview else { return }
        container.addSubview(self, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: content.leadingAnchor),
            trailingAnchor.constraint(equalTo: content.trailingAnchor),
            topAnchor.constraint(equalTo: content.topAnchor),
            bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        if isPresented {
            updateModalState()
        }
        eventMonitor = eventMonitoring.install { [weak self] event in
            guard let self else { return event }
            return handle(event)
        }
    }

    func detach() {
        if underlyingContent != nil {
            restoreUnderlyingContent()
        }
        if let eventMonitor {
            eventMonitoring.remove(eventMonitor)
            self.eventMonitor = nil
        }
        removeFromSuperview()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isPresented ? super.hitTest(point) : nil
    }

    /// Consume outside presses before native toolbar controls or window dragging
    /// receive them. Keep all events in other windows untouched.
    func handle(_ event: NSEvent) -> NSEvent? {
        guard isPresented, let window, event.window === window else { return event }
        if event.type == .keyDown {
            if event.keyCode == 48, event.modifierFlags.isDisjoint(with: [.command, .control, .option]) {
                moveFocus(backward: event.modifierFlags.contains(.shift))
                return nil
            }
            guard event.keyCode == 53 else { return event }
            onEscape()
            return nil
        }
        let point = convert(event.locationInWindow, from: nil)
        let panelWidth = SettingsSidePanelLayout.resolvedWidth(requested: requestedWidth, available: bounds.width)
        if point.x < bounds.maxX - panelWidth || !bounds.contains(point) {
            onDismiss()
            return nil
        }
        return event
    }
}

public extension View {
    /// Presents a drawer across the Settings window, including its toolbar band.
    func windowSidePanel(
        isPresented: Bool,
        width: CGFloat = AppDesignSystem.Layout.modeEditorPanelWidth,
        onDismiss: @escaping () -> Void,
        onEscape: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        background {
            SettingsWindowPanelBridge(
                isPresented: isPresented,
                width: width,
                onDismiss: onDismiss,
                onEscape: onEscape,
                panelContent: content
            )
            .frame(width: 0, height: 0)
        }
    }
}

#Preview("Window panel bridge") {
    Color.clear
        .windowSidePanel(isPresented: true, onDismiss: {}, content: {
            Color.clear
        })
        .frame(width: 900, height: 700)
}

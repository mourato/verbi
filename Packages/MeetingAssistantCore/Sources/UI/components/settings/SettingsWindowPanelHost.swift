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
        anchor.host.isPresented = isPresented
        anchor.host.requestedWidth = width
        anchor.host.onDismiss = onDismiss
        anchor.host.onEscape = onEscape ?? onDismiss
        // Reuse the existing drawer's material, separators, clearance and motion.
        anchor.host.hostingController.rootView = AnyView(
            Color.clear
                .settingsSidePanel(
                    isPresented: isPresented,
                    width: width,
                    onDismiss: onDismiss,
                    onEscape: onEscape,
                    content: panelContent
                )
                .ignoresSafeArea()
                .environment(\.self, context.environment)
        )
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
    var isPresented = false
    var requestedWidth: CGFloat = 0
    var onDismiss: () -> Void = {}
    var onEscape: () -> Void = {}
    private var eventMonitor: Any?

    init() {
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
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }
            return handle(event)
        }
    }

    func detach() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
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

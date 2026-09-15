import AppKit
import MeetingAssistantCoreCommon
import SwiftUI

struct SettingsWindowConfigurator: NSViewRepresentable {
    private enum Layout {
        static let minimumSize = NSSize(width: 900, height: 640)
    }

    final class Coordinator {
        var isConfigured = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window, !context.coordinator.isConfigured else { return }
            context.coordinator.isConfigured = true
            configure(window: window, orderFront: true)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        // Only configure if makeNSView didn't have window attached yet
        guard !context.coordinator.isConfigured else { return }
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window, !context.coordinator.isConfigured else { return }
            context.coordinator.isConfigured = true
            configure(window: window, orderFront: false)
        }
    }

    private func configure(window: NSWindow?, orderFront: Bool) {
        guard let window else { return }

        let requiredStyleMask: NSWindow.StyleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable,
            .fullSizeContentView
        ]
        window.styleMask.formUnion(requiredStyleMask)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isOpaque = false
        window.isMovableByWindowBackground = true
        window.minSize = Layout.minimumSize
        window.setFrameAutosaveName(AppIdentity.settingsWindowAutosaveName)

        if orderFront {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

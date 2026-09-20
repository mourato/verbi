import AppKit
import MeetingAssistantCoreCommon
import SwiftUI

/// Patches the SwiftUI-owned Settings window to the shared chrome contract:
/// 900x700, fixed sidebar layout, native minimal toolbar with inline pane
/// title, no separator hairline, opaque, not draggable by content.
struct SettingsWindowConfigurator: NSViewRepresentable {
    private enum Layout {
        static let contentSize = NSSize(width: 900, height: 700)
    }

    /// Inline toolbar title; the detail selection owns it.
    var title: String

    final class Coordinator: NSObject, NSToolbarDelegate {
        var isConfigured = false

        // MARK: - NSToolbarDelegate

        func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
            [.sidebarTrackingSeparator]
        }

        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            toolbarDefaultItemIdentifiers(toolbar)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        let title = title
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            configure(window: window, title: title, coordinator: context.coordinator, orderFront: true)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        let title = title
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            if !context.coordinator.isConfigured {
                configure(window: window, title: title, coordinator: context.coordinator, orderFront: false)
            } else {
                syncTitle(window: window, title: title)
            }
        }
    }

    private func configure(window: NSWindow, title: String, coordinator: Coordinator, orderFront: Bool) {
        guard !coordinator.isConfigured else {
            syncTitle(window: window, title: title)
            return
        }
        coordinator.isConfigured = true

        let requiredStyleMask: NSWindow.StyleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable,
            .fullSizeContentView
        ]
        window.styleMask.formUnion(requiredStyleMask)
        // Opaque titlebar with the system glass band drawn; the title sits inline leading.
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        // `.automatic` draws a hairline once content scrolls under the bar, splitting the surface.
        window.titlebarSeparatorStyle = .none
        // Stock Settings isn't dragged by its content — a drag on a `Form` shouldn't move the window.
        window.isMovableByWindowBackground = false
        window.backgroundColor = nil
        window.isOpaque = true
        window.minSize = Layout.contentSize
        window.contentMinSize = Layout.contentSize
        window.setFrameAutosaveName(AppIdentity.settingsWindowAutosaveName)

        installToolbarIfNeeded(window: window, coordinator: coordinator)
        syncTitle(window: window, title: title)

        if orderFront {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func installToolbarIfNeeded(window: NSWindow, coordinator: Coordinator) {
        guard window.toolbar == nil else { return }
        let toolbar = NSToolbar(identifier: "SettingsToolbarMinimal")
        toolbar.delegate = coordinator
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.allowsDisplayModeCustomization = false
        window.toolbar = toolbar
    }

    private func syncTitle(window: NSWindow, title: String) {
        window.title = title
    }
}

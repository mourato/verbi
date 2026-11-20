import AppKit
import SwiftUI
import VerbiCoreCommon

struct SettingsWindowConfigurator: NSViewRepresentable {
    private enum Layout {
        static let contentSize = NSSize(width: 900, height: 700)
    }

    var title: String

    final class Coordinator: NSObject, NSToolbarDelegate {
        var isConfigured = false

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
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
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

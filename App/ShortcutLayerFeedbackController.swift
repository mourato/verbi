import AppKit

@MainActor
final class ShortcutLayerFeedbackController {
    private var window: NSPanel?
    private var hideTask: Task<Void, Never>?

    func showArmed() {
        show(message: "⌨︎")
    }

    func showCancelled() {
        show(message: "×")
    }

    func showTriggered() {
        show(message: "✓")
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        window?.orderOut(nil)
    }

    private func show(message: String) {
        hideTask?.cancel()

        let panel = makeOrReusePanel()
        if let textField = panel.contentView?.subviews.first as? NSTextField {
            textField.stringValue = message
        }

        position(panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            panel.animator().alphaValue = 1
        }

        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 0
            } completionHandler: {
                Task { @MainActor in
                    panel.orderOut(nil)
                    panel.alphaValue = 1
                }
            }
        }
    }

    private func makeOrReusePanel() -> NSPanel {
        if let window {
            return window
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 46, height: 30),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let container = NSView(frame: panel.contentView!.bounds)
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.8).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor

        let label = NSTextField(labelWithString: "⌨︎")
        label.alignment = .center
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.frame = container.bounds
        label.autoresizingMask = [.width, .height]

        container.addSubview(label)
        panel.contentView = container

        window = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screenFrame = NSScreen.main?.visibleFrame else {
            return
        }

        let originX = screenFrame.midX - (panel.frame.width / 2)
        let originY = screenFrame.maxY - panel.frame.height - 20
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }
}

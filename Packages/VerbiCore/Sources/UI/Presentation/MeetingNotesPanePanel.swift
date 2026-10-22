import AppKit

@MainActor
final class MeetingNotesPanePanel: NSPanel {
    static let cornerRadius: CGFloat = 14

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }

    func applyCollectionBehavior(showOnAllSpaces: Bool) {
        var behavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary]
        if showOnAllSpaces {
            behavior.insert(.canJoinAllSpaces)
        }
        collectionBehavior = behavior
    }

    func applyScreenCaptureVisibility(hidden: Bool) {
        sharingType = hidden ? .none : .readOnly
    }
}

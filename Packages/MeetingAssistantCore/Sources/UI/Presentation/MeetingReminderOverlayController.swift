import AppKit
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import SwiftUI

@MainActor
public final class MeetingReminderOverlayController {
    private var windows: [MeetingReminderOverlayWindow] = []
    private var previousApp: NSRunningApplication?
    private var screenChangeObserver: NSObjectProtocol?
    private var activePresentation: Presentation?

    private struct Presentation {
        let event: MeetingCalendarEventSnapshot
        let prefersRecordPrimary: Bool
        let mirrorOnAllScreens: Bool
        let playAlertSound: Bool
        let actionHandler: MeetingReminderActionHandling
    }

    public init() {}

    public var isVisible: Bool {
        !windows.isEmpty
    }

    public func show(
        event: MeetingCalendarEventSnapshot,
        prefersRecordPrimary: Bool,
        mirrorOnAllScreens: Bool,
        playAlertSound: Bool,
        actionHandler: MeetingReminderActionHandling
    ) {
        let presentation = Presentation(
            event: event,
            prefersRecordPrimary: prefersRecordPrimary,
            mirrorOnAllScreens: mirrorOnAllScreens,
            playAlertSound: playAlertSound,
            actionHandler: actionHandler
        )

        if windows.isEmpty {
            previousApp = NSWorkspace.shared.frontmostApplication
        }

        activePresentation = presentation
        buildWindows(for: presentation)
        registerScreenChangeObserver()

        if presentation.playAlertSound {
            NSSound.beep()
        }

        NSApp.activate(ignoringOtherApps: true)
        let keyWindow = windows.first(where: { $0.screen == NSScreen.main }) ?? windows.first
        keyWindow?.makeKeyAndOrderFront(nil)
        windows.forEach { $0.orderFrontRegardless() }
    }

    public func hide() {
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
            self.screenChangeObserver = nil
        }
        activePresentation = nil
        teardownWindows()
        previousApp?.activate(options: [])
        previousApp = nil
    }

    private func buildWindows(for presentation: Presentation) {
        teardownWindows()

        let targetScreens: [NSScreen] = if presentation.mirrorOnAllScreens, !NSScreen.screens.isEmpty {
            NSScreen.screens
        } else if let main = NSScreen.main {
            [main]
        } else {
            []
        }

        for screen in targetScreens {
            let window = makeWindow(frame: screen.frame)
            let rootView = MeetingReminderAlertView(
                event: presentation.event,
                prefersRecordPrimary: presentation.prefersRecordPrimary,
                onPrimary: { [weak self] in
                    self?.performPrimaryAction(presentation: presentation)
                },
                onJoin: { presentation.actionHandler.joinMeeting(for: presentation.event) },
                onNotes: { presentation.actionHandler.openNotes(for: presentation.event) },
                onDismiss: { presentation.actionHandler.dismissReminder(for: presentation.event) },
                onSnooze: { minutes in
                    presentation.actionHandler.snoozeReminder(for: presentation.event, minutes: minutes)
                },
                onSnoozeUntilEnd: {
                    presentation.actionHandler.snoozeReminderUntilEnd(for: presentation.event)
                }
            )

            let hosting = NSHostingView(rootView: rootView)
            hosting.sizingOptions = []
            hosting.autoresizingMask = [.width, .height]
            window.contentView = hosting
            window.setFrame(screen.frame, display: true)
            hosting.frame = CGRect(origin: .zero, size: screen.frame.size)
            window.onCancel = { presentation.actionHandler.dismissReminder(for: presentation.event) }
            window.onPrimaryAction = { [weak self] in
                self?.performPrimaryAction(presentation: presentation)
            }
            windows.append(window)
        }
    }

    private func performPrimaryAction(presentation: Presentation) {
        if presentation.prefersRecordPrimary {
            Task {
                await presentation.actionHandler.recordMeeting(for: presentation.event)
            }
        } else if presentation.event.joinURL != nil {
            presentation.actionHandler.joinMeeting(for: presentation.event)
        } else {
            presentation.actionHandler.dismissReminder(for: presentation.event)
        }
    }

    private func teardownWindows() {
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows.removeAll()
    }

    private func registerScreenChangeObserver() {
        guard screenChangeObserver == nil else { return }
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let presentation = self.activePresentation else { return }
                self.buildWindows(for: presentation)
                let keyWindow = self.windows.first(where: { $0.screen == NSScreen.main }) ?? self.windows.first
                keyWindow?.makeKeyAndOrderFront(nil)
                self.windows.forEach { $0.orderFrontRegardless() }
            }
        }
    }

    private func makeWindow(frame: NSRect) -> MeetingReminderOverlayWindow {
        let window = MeetingReminderOverlayWindow(
            contentRect: frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.isMovable = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        return window
    }
}

final class MeetingReminderOverlayWindow: NSWindow {
    var onCancel: (() -> Void)?
    var onPrimaryAction: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func cancelOperation(_: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            onCancel?()
        case 36, 76:
            onPrimaryAction?()
        default:
            super.keyDown(with: event)
        }
    }
}

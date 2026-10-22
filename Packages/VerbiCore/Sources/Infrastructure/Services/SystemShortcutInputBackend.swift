import AppKit
import Foundation

@MainActor
public final class SystemShortcutInputBackend: ShortcutInputBackend {
    private var flagsChangedMonitor: KeyboardEventMonitor?
    private var keyDownMonitor: KeyboardEventMonitor?
    private var keyUpMonitor: KeyboardEventMonitor?

    private var flagsChangedHandler: EventHandler?
    private var keyDownHandler: EventHandler?
    private var keyUpHandler: EventHandler?

    public var isFlagsChangedMonitoringActive: Bool {
        flagsChangedMonitor != nil
    }

    public var isKeyDownMonitoringActive: Bool {
        keyDownMonitor != nil
    }

    public var isKeyUpMonitoringActive: Bool {
        keyUpMonitor != nil
    }

    public init() {}

    public func setFlagsChangedHandler(_ handler: EventHandler?) {
        flagsChangedHandler = handler
    }

    public func setKeyDownHandler(_ handler: EventHandler?) {
        keyDownHandler = handler
    }

    public func setKeyUpHandler(_ handler: EventHandler?) {
        keyUpHandler = handler
    }

    public func startFlagsChangedMonitoring() {
        guard flagsChangedMonitor == nil else {
            return
        }

        flagsChangedMonitor = KeyboardEventMonitor(mask: .flagsChanged) { [weak self] event in
            let inputEvent = ShortcutInputEvent(systemEvent: event)
            Task { @MainActor [weak self] in
                self?.flagsChangedHandler?(inputEvent)
            }
        }
        flagsChangedMonitor?.start()
    }

    public func stopFlagsChangedMonitoring() {
        flagsChangedMonitor?.stop()
        flagsChangedMonitor = nil
    }

    public func startKeyDownMonitoring(shouldReturnLocalEvent: LocalPropagationPolicy?) {
        guard keyDownMonitor == nil else {
            return
        }

        if let shouldReturnLocalEvent {
            keyDownMonitor = KeyboardEventMonitor(
                mask: .keyDown,
                shouldReturnLocalEvent: { event in
                    shouldReturnLocalEvent(ShortcutInputEvent(systemEvent: event))
                },
                handler: { [weak self] event in
                    let inputEvent = ShortcutInputEvent(systemEvent: event)
                    Task { @MainActor [weak self] in
                        self?.keyDownHandler?(inputEvent)
                    }
                }
            )
        } else {
            keyDownMonitor = KeyboardEventMonitor(mask: .keyDown) { [weak self] event in
                let inputEvent = ShortcutInputEvent(systemEvent: event)
                Task { @MainActor [weak self] in
                    self?.keyDownHandler?(inputEvent)
                }
            }
        }

        keyDownMonitor?.start()
    }

    public func stopKeyDownMonitoring() {
        keyDownMonitor?.stop()
        keyDownMonitor = nil
    }

    public func startKeyUpMonitoring() {
        guard keyUpMonitor == nil else {
            return
        }

        keyUpMonitor = KeyboardEventMonitor(mask: .keyUp) { [weak self] event in
            let inputEvent = ShortcutInputEvent(systemEvent: event)
            Task { @MainActor [weak self] in
                self?.keyUpHandler?(inputEvent)
            }
        }
        keyUpMonitor?.start()
    }

    public func stopKeyUpMonitoring() {
        keyUpMonitor?.stop()
        keyUpMonitor = nil
    }

    public func stopAllMonitoring() {
        stopFlagsChangedMonitoring()
        stopKeyDownMonitoring()
        stopKeyUpMonitoring()
    }
}

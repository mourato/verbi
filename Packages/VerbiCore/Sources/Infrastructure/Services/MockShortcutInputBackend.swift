import AppKit
import Foundation

@MainActor
public final class MockShortcutInputBackend: ShortcutInputBackend {
    private var flagsChangedHandler: EventHandler?
    private var keyDownHandler: EventHandler?
    private var keyUpHandler: EventHandler?

    public private(set) var isFlagsChangedMonitoringActive: Bool = false
    public private(set) var isKeyDownMonitoringActive: Bool = false
    public private(set) var isKeyUpMonitoringActive: Bool = false

    private var eventQueue: [ShortcutInputEvent] = []

    public var autoReplay: Bool = true

    public var replayDelay: TimeInterval = 0

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
        isFlagsChangedMonitoringActive = true
    }

    public func stopFlagsChangedMonitoring() {
        isFlagsChangedMonitoringActive = false
    }

    public func startKeyDownMonitoring(shouldReturnLocalEvent _: LocalPropagationPolicy?) {
        isKeyDownMonitoringActive = true
    }

    public func stopKeyDownMonitoring() {
        isKeyDownMonitoringActive = false
    }

    public func startKeyUpMonitoring() {
        isKeyUpMonitoringActive = true
    }

    public func stopKeyUpMonitoring() {
        isKeyUpMonitoringActive = false
    }

    public func stopAllMonitoring() {
        isFlagsChangedMonitoringActive = false
        isKeyDownMonitoringActive = false
        isKeyUpMonitoringActive = false
    }

    public func queueEvent(_ event: ShortcutInputEvent) {
        eventQueue.append(event)
    }

    public func queueEvents(_ events: [ShortcutInputEvent]) {
        eventQueue.append(contentsOf: events)
    }

    @discardableResult
    public func injectNextEvent() -> ShortcutInputEvent? {
        guard !eventQueue.isEmpty else { return nil }

        let event = eventQueue.removeFirst()
        dispatchEvent(event)
        return event
    }

    public func replayAllEvents() {
        while !eventQueue.isEmpty {
            _ = injectNextEvent()
        }
    }

    public func clearQueue() {
        eventQueue.removeAll()
    }

    public var queuedEventCount: Int {
        eventQueue.count
    }

    public func injectEvent(_ event: ShortcutInputEvent) {
        dispatchEvent(event)
    }

    private func dispatchEvent(_ event: ShortcutInputEvent) {
        switch event.kind {
        case .flagsChanged:
            flagsChangedHandler?(event)
        case .keyDown:
            keyDownHandler?(event)
        case .keyUp:
            keyUpHandler?(event)
        }
    }

    public static func withEvents(_ events: [ShortcutInputEvent]) -> MockShortcutInputBackend {
        let backend = MockShortcutInputBackend()
        backend.queueEvents(events)
        return backend
    }
}

public extension ShortcutInputEvent {
    static func keyDown(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        isRepeat: Bool = false,
        characters: String? = nil
    ) -> ShortcutInputEvent {
        ShortcutInputEvent(
            kind: .keyDown,
            keyCode: keyCode,
            modifierFlagsRawValue: modifiers.rawValue,
            isRepeat: isRepeat,
            charactersIgnoringModifiers: characters
        )
    }

    static func keyUp(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        characters: String? = nil
    ) -> ShortcutInputEvent {
        ShortcutInputEvent(
            kind: .keyUp,
            keyCode: keyCode,
            modifierFlagsRawValue: modifiers.rawValue,
            isRepeat: false,
            charactersIgnoringModifiers: characters
        )
    }

    static func flagsChanged(
        modifiers: NSEvent.ModifierFlags
    ) -> ShortcutInputEvent {
        ShortcutInputEvent(
            kind: .flagsChanged,
            keyCode: 0,
            modifierFlagsRawValue: modifiers.rawValue,
            isRepeat: false,
            charactersIgnoringModifiers: nil
        )
    }
}

public struct ShortcutTestSequence {
    public let events: [ShortcutInputEvent]

    public static func modifierPress(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> [ShortcutInputEvent] {
        [
            .flagsChanged(modifiers: flags),
            .keyDown(keyCode: keyCode, modifiers: flags),
            .keyUp(keyCode: keyCode, modifiers: []),
            .flagsChanged(modifiers: [])
        ]
    }

    public static func keyPress(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> [ShortcutInputEvent] {
        [
            .keyDown(keyCode: keyCode, modifiers: modifiers),
            .keyUp(keyCode: keyCode, modifiers: modifiers)
        ]
    }

    public static func shortcutPress(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> [ShortcutInputEvent] {
        [
            .flagsChanged(modifiers: modifiers),
            .keyDown(keyCode: keyCode, modifiers: modifiers),
            .keyUp(keyCode: keyCode, modifiers: modifiers),
            .flagsChanged(modifiers: [])
        ]
    }
}

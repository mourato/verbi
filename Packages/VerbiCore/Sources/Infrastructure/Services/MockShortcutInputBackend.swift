import AppKit
import Foundation

/// A test-only implementation of ShortcutInputBackend that allows deterministic replay of event sequences.
/// This backend does NOT monitor real system events - instead, events are injected programmatically
/// via the `injectEvent()` method, making it ideal for unit tests and replay scenarios.
@MainActor
public final class MockShortcutInputBackend: ShortcutInputBackend {
    // MARK: - Properties

    private var flagsChangedHandler: EventHandler?
    private var keyDownHandler: EventHandler?
    private var keyUpHandler: EventHandler?

    public private(set) var isFlagsChangedMonitoringActive: Bool = false
    public private(set) var isKeyDownMonitoringActive: Bool = false
    public private(set) var isKeyUpMonitoringActive: Bool = false

    /// Queue of events to replay in order
    private var eventQueue: [ShortcutInputEvent] = []

    /// Whether the backend should automatically replay events (synchronously)
    public var autoReplay: Bool = true

    /// If set, events are delayed by this amount (for simulating real timing)
    public var replayDelay: TimeInterval = 0

    // MARK: - Initialization

    public init() {}

    // MARK: - ShortcutInputBackend

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

    // MARK: - Test Utilities

    /// Queues an event for replay. Events are replayed in FIFO order.
    public func queueEvent(_ event: ShortcutInputEvent) {
        eventQueue.append(event)
    }

    /// Queues multiple events for replay.
    public func queueEvents(_ events: [ShortcutInputEvent]) {
        eventQueue.append(contentsOf: events)
    }

    /// Injects the next queued event to the appropriate handler.
    /// Returns the injected event, or nil if no events are queued.
    @discardableResult
    public func injectNextEvent() -> ShortcutInputEvent? {
        guard !eventQueue.isEmpty else { return nil }

        let event = eventQueue.removeFirst()
        dispatchEvent(event)
        return event
    }

    /// Injects all queued events synchronously.
    public func replayAllEvents() {
        while !eventQueue.isEmpty {
            _ = injectNextEvent()
        }
    }

    /// Clears all queued events.
    public func clearQueue() {
        eventQueue.removeAll()
    }

    /// Returns the number of queued events.
    public var queuedEventCount: Int {
        eventQueue.count
    }

    /// Injects a specific event directly (bypasses queue).
    public func injectEvent(_ event: ShortcutInputEvent) {
        dispatchEvent(event)
    }

    // MARK: - Private

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

    // MARK: - Factory

    /// Creates a backend pre-configured with a specific event sequence for testing.
    public static func withEvents(_ events: [ShortcutInputEvent]) -> MockShortcutInputBackend {
        let backend = MockShortcutInputBackend()
        backend.queueEvents(events)
        return backend
    }
}

// MARK: - Test Event Builders

public extension ShortcutInputEvent {
    /// Creates a keyDown event for testing.
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

    /// Creates a keyUp event for testing.
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

    /// Creates a flagsChanged event for testing.
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

// MARK: - Common Test Sequences

public struct ShortcutTestSequence {
    public let events: [ShortcutInputEvent]

    /// Creates a press-and-release sequence for a modifier key (e.g., Control pressed and released)
    public static func modifierPress(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> [ShortcutInputEvent] {
        [
            .flagsChanged(modifiers: flags),
            .keyDown(keyCode: keyCode, modifiers: flags),
            .keyUp(keyCode: keyCode, modifiers: []),
            .flagsChanged(modifiers: [])
        ]
    }

    /// Creates a simple key press (down + up)
    public static func keyPress(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> [ShortcutInputEvent] {
        [
            .keyDown(keyCode: keyCode, modifiers: modifiers),
            .keyUp(keyCode: keyCode, modifiers: modifiers)
        ]
    }

    /// Creates a modifier + key combination (e.g., Cmd+S)
    public static func shortcutPress(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> [ShortcutInputEvent] {
        [
            .flagsChanged(modifiers: modifiers),
            .keyDown(keyCode: keyCode, modifiers: modifiers),
            .keyUp(keyCode: keyCode, modifiers: modifiers),
            .flagsChanged(modifiers: [])
        ]
    }
}

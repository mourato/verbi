import AppKit
import Foundation

public final class KeyboardEventMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent) -> Void
    private let shouldReturnEvent: Bool
    private let shouldReturnLocalEvent: ((NSEvent) -> Bool)?

    public init(
        mask: NSEvent.EventTypeMask,
        shouldReturnEvent: Bool = true,
        handler: @escaping (NSEvent) -> Void
    ) {
        self.mask = mask
        self.shouldReturnEvent = shouldReturnEvent
        shouldReturnLocalEvent = nil
        self.handler = handler
    }

    public init(
        mask: NSEvent.EventTypeMask,
        shouldReturnLocalEvent: @escaping (NSEvent) -> Bool,
        handler: @escaping (NSEvent) -> Void
    ) {
        self.mask = mask
        shouldReturnEvent = true
        self.shouldReturnLocalEvent = shouldReturnLocalEvent
        self.handler = handler
    }

    public func start() {
        stop()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handler(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handler(event)
            guard let self else {
                return event
            }

            let shouldReturn = shouldReturnLocalEvent?(event) ?? shouldReturnEvent
            return shouldReturn ? event : nil
        }
    }

    public func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }

        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    deinit {
        stop()
    }
}

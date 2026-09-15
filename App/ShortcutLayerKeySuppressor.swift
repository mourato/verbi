import AppKit
import CoreGraphics
import MeetingAssistantCore

final class ShortcutLayerKeySuppressor {
    enum StartFailureReason: String {
        case eventTapCreationFailed = "event_tap_creation_failed"
        case runLoopSourceCreationFailed = "runloop_source_creation_failed"
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var suppressedKeyCodes = Set<UInt16>()
    private var keyDownHandler: ((NSEvent) -> Bool)?
    private(set) var lastStartFailureReason: StartFailureReason?

    var isActive: Bool {
        eventTap != nil && runLoopSource != nil
    }

    @discardableResult
    func start(keyDownHandler: @escaping (NSEvent) -> Bool) -> Bool {
        guard eventTap == nil else {
            lastStartFailureReason = nil
            return true
        }

        self.keyDownHandler = keyDownHandler

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let suppressor = Unmanaged<ShortcutLayerKeySuppressor>
                .fromOpaque(userInfo)
                .takeUnretainedValue()
            return suppressor.handle(type: type, event: event)
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            lastStartFailureReason = .eventTapCreationFailed
            AppLogger.warning(
                "Failed to create shortcut layer key suppressor tap",
                category: .assistant
            )
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        guard let source else {
            lastStartFailureReason = .runLoopSourceCreationFailed
            AppLogger.warning(
                "Failed to create runloop source for shortcut layer key suppressor",
                category: .assistant
            )
            self.keyDownHandler = nil
            return false
        }

        lastStartFailureReason = nil
        self.eventTap = eventTap
        runLoopSource = source

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        runLoopSource = nil
        eventTap = nil
        suppressedKeyCodes.removeAll()
        keyDownHandler = nil
        lastStartFailureReason = nil
    }

    deinit {
        stop()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        case .keyDown:
            guard let nsEvent = NSEvent(cgEvent: event) else {
                return Unmanaged.passUnretained(event)
            }

            guard keyDownHandler?(nsEvent) == true else {
                return Unmanaged.passUnretained(event)
            }

            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            suppressedKeyCodes.insert(keyCode)
            return nil
        case .keyUp:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            guard suppressedKeyCodes.contains(keyCode) else {
                return Unmanaged.passUnretained(event)
            }
            suppressedKeyCodes.remove(keyCode)
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}

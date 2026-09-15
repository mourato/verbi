import AppKit
import MeetingAssistantCore

@MainActor
final class ShortcutActivationState {
    private var leftCommandIsDown = false
    private var rightCommandIsDown = false
    private var leftOptionIsDown = false
    private var rightOptionIsDown = false
    private var leftShiftIsDown = false
    private var rightShiftIsDown = false
    private var leftControlIsDown = false
    private var rightControlIsDown = false
    private var fnIsDown = false
    private var pressedKeyCodes = Set<UInt16>()

    func reset() {
        leftCommandIsDown = false
        rightCommandIsDown = false
        leftOptionIsDown = false
        rightOptionIsDown = false
        leftShiftIsDown = false
        rightShiftIsDown = false
        leftControlIsDown = false
        rightControlIsDown = false
        fnIsDown = false
        pressedKeyCodes.removeAll()
    }

    func isPresetActive(_ preset: PresetShortcutKey, event: NSEvent) -> Bool {
        isPresetActive(preset, inputEvent: ShortcutInputEvent(systemEvent: event))
    }

    func isPresetActive(_ preset: PresetShortcutKey, inputEvent: ShortcutInputEvent) -> Bool {
        let flags = normalizedFlags(rawValue: inputEvent.modifierFlagsRawValue)
        updateTrackedModifierState(inputEvent: inputEvent, flags: flags)

        switch preset {
        case .rightCommand:
            return rightCommandIsDown && matchesModifiers(flags, required: .command)
        case .rightOption:
            return rightOptionIsDown && matchesModifiers(flags, required: .option)
        case .rightShift:
            return rightShiftIsDown && matchesModifiers(flags, required: .shift)
        case .rightControl:
            return rightControlIsDown && matchesModifiers(flags, required: .control)
        case .fn:
            return fnIsDown && matchesModifiers(flags, required: .function)
        case .optionCommand:
            return matchesModifiers(flags, required: [.option, .command])
        case .controlCommand:
            return matchesModifiers(flags, required: [.control, .command])
        case .controlOption:
            return matchesModifiers(flags, required: [.control, .option])
        case .shiftCommand:
            return matchesModifiers(flags, required: [.shift, .command])
        case .optionShift:
            return matchesModifiers(flags, required: [.option, .shift])
        case .controlShift:
            return matchesModifiers(flags, required: [.control, .shift])
        case .notSpecified, .custom:
            return false
        }
    }

    func isModifierGestureActive(_ gesture: ModifierShortcutGesture, event: NSEvent) -> Bool {
        isModifierGestureActive(gesture, inputEvent: ShortcutInputEvent(systemEvent: event))
    }

    func isModifierGestureActive(_ gesture: ModifierShortcutGesture, inputEvent: ShortcutInputEvent) -> Bool {
        let flags = normalizedFlags(rawValue: inputEvent.modifierFlagsRawValue)
        updateTrackedModifierState(inputEvent: inputEvent, flags: flags)
        return matchesGesture(gesture, flags: flags)
    }

    func isShortcutActive(_ definition: ShortcutDefinition, event: NSEvent) -> Bool {
        isShortcutActive(definition, inputEvent: ShortcutInputEvent(systemEvent: event))
    }

    func isShortcutActive(_ definition: ShortcutDefinition, inputEvent: ShortcutInputEvent) -> Bool {
        let flags = normalizedFlags(rawValue: inputEvent.modifierFlagsRawValue)
        updateTrackedModifierState(inputEvent: inputEvent, flags: flags)

        guard matchesModifierSet(Set(definition.modifiers), flags: flags) else {
            return false
        }

        guard let primaryKey = definition.primaryKey else {
            return true
        }

        return pressedKeyCodes.contains(primaryKey.keyCode)
    }

    private func updateTrackedModifierState(
        event: NSEvent,
        flags: NSEvent.ModifierFlags
    ) {
        updateTrackedModifierState(
            inputEvent: ShortcutInputEvent(systemEvent: event),
            flags: flags
        )
    }

    private func updateTrackedModifierState(
        inputEvent: ShortcutInputEvent,
        flags: NSEvent.ModifierFlags
    ) {
        if inputEvent.kind == .keyDown {
            pressedKeyCodes.insert(inputEvent.keyCode)
        } else if inputEvent.kind == .keyUp {
            pressedKeyCodes.remove(inputEvent.keyCode)
        }

        switch inputEvent.keyCode {
        case PresetShortcutKey.leftCommandKeyCode:
            leftCommandIsDown.toggle()
        case PresetShortcutKey.rightCommandKeyCode:
            rightCommandIsDown.toggle()
        case PresetShortcutKey.leftOptionKeyCode:
            leftOptionIsDown.toggle()
        case PresetShortcutKey.rightOptionKeyCode:
            rightOptionIsDown.toggle()
        case PresetShortcutKey.leftShiftKeyCode:
            leftShiftIsDown.toggle()
        case PresetShortcutKey.rightShiftKeyCode:
            rightShiftIsDown.toggle()
        case PresetShortcutKey.leftControlKeyCode:
            leftControlIsDown.toggle()
        case PresetShortcutKey.rightControlKeyCode:
            rightControlIsDown.toggle()
        case PresetShortcutKey.fnKeyCode:
            fnIsDown.toggle()
        default:
            break
        }

        if !flags.contains(.command) {
            leftCommandIsDown = false
            rightCommandIsDown = false
        }
        if !flags.contains(.option) {
            leftOptionIsDown = false
            rightOptionIsDown = false
        }
        if !flags.contains(.shift) {
            leftShiftIsDown = false
            rightShiftIsDown = false
        }
        if !flags.contains(.control) {
            leftControlIsDown = false
            rightControlIsDown = false
        }
        if !flags.contains(.function) {
            fnIsDown = false
        }
    }

    private func matchesGesture(
        _ gesture: ModifierShortcutGesture,
        flags: NSEvent.ModifierFlags
    ) -> Bool {
        let required = Set(gesture.keys)
        return matchesModifierSet(required, flags: flags)
    }

    private func matchesModifierSet(
        _ required: Set<ModifierShortcutKey>,
        flags: NSEvent.ModifierFlags
    ) -> Bool {
        guard !required.isEmpty else {
            return false
        }

        guard matchesModifierFamily(
            required: required,
            anyFlagActive: flags.contains(.command),
            leftIsDown: leftCommandIsDown,
            rightIsDown: rightCommandIsDown,
            anyKey: .command,
            leftKey: .leftCommand,
            rightKey: .rightCommand
        ) else {
            return false
        }

        guard matchesModifierFamily(
            required: required,
            anyFlagActive: flags.contains(.shift),
            leftIsDown: leftShiftIsDown,
            rightIsDown: rightShiftIsDown,
            anyKey: .shift,
            leftKey: .leftShift,
            rightKey: .rightShift
        ) else {
            return false
        }

        guard matchesModifierFamily(
            required: required,
            anyFlagActive: flags.contains(.option),
            leftIsDown: leftOptionIsDown,
            rightIsDown: rightOptionIsDown,
            anyKey: .option,
            leftKey: .leftOption,
            rightKey: .rightOption
        ) else {
            return false
        }

        guard matchesModifierFamily(
            required: required,
            anyFlagActive: flags.contains(.control),
            leftIsDown: leftControlIsDown,
            rightIsDown: rightControlIsDown,
            anyKey: .control,
            leftKey: .leftControl,
            rightKey: .rightControl
        ) else {
            return false
        }

        let requiresFn = required.contains(.fn)
        if requiresFn != fnIsDown {
            return false
        }

        return true
    }

    private func matchesModifierFamily(
        required: Set<ModifierShortcutKey>,
        anyFlagActive: Bool,
        leftIsDown: Bool,
        rightIsDown: Bool,
        anyKey: ModifierShortcutKey,
        leftKey: ModifierShortcutKey,
        rightKey: ModifierShortcutKey
    ) -> Bool {
        let requiresAny = required.contains(anyKey)
        let requiresLeft = required.contains(leftKey)
        let requiresRight = required.contains(rightKey)

        if requiresAny, !anyFlagActive {
            return false
        }
        if requiresLeft, !leftIsDown {
            return false
        }
        if requiresRight, !rightIsDown {
            return false
        }

        if !requiresAny {
            if !requiresLeft, leftIsDown {
                return false
            }
            if !requiresRight, rightIsDown {
                return false
            }
        }

        return true
    }

    private func matchesModifiers(
        _ flags: NSEvent.ModifierFlags,
        required: NSEvent.ModifierFlags
    ) -> Bool {
        guard flags.contains(required) else {
            return false
        }

        let extras = flags.subtracting(required)
        return extras.isEmpty
    }

    private func normalizedFlags(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad])
    }

    private func normalizedFlags(rawValue: UInt) -> NSEvent.ModifierFlags {
        normalizedFlags(NSEvent.ModifierFlags(rawValue: rawValue))
    }
}

extension PresetShortcutKey {
    static let leftCommandKeyCode: UInt16 = 0x37
    static let rightCommandKeyCode: UInt16 = 0x36
    static let leftOptionKeyCode: UInt16 = 0x3A
    static let rightOptionKeyCode: UInt16 = 0x3D
    static let leftShiftKeyCode: UInt16 = 0x38
    static let rightShiftKeyCode: UInt16 = 0x3C
    static let leftControlKeyCode: UInt16 = 0x3B
    static let rightControlKeyCode: UInt16 = 0x3E
    static let fnKeyCode: UInt16 = 0x3F
    static let escapeKeyCode: UInt16 = 0x35

    var requiresModifierMonitoring: Bool {
        switch self {
        case .notSpecified, .custom:
            false
        case .rightCommand, .rightOption, .rightShift, .rightControl, .fn:
            true
        case .optionCommand, .controlCommand, .controlOption, .shiftCommand, .optionShift, .controlShift:
            true
        }
    }
}

enum ShortcutCaptureHealthResult: String {
    case idle
    case healthy
    case degraded
}

struct ShortcutCaptureBackendExpectation: Equatable {
    let needsGlobalCapture: Bool
    let needsFlagsMonitor: Bool
    let needsKeyDownMonitor: Bool
    let needsKeyUpMonitor: Bool
    let needsEventTap: Bool

    static let none = ShortcutCaptureBackendExpectation(
        needsGlobalCapture: false,
        needsFlagsMonitor: false,
        needsKeyDownMonitor: false,
        needsKeyUpMonitor: false,
        needsEventTap: false
    )
}

struct ShortcutCaptureHealthSnapshot: Equatable {
    let pipeline: String
    let scope: String
    let source: String
    let checkedAt: Date
    let result: ShortcutCaptureHealthResult
    let requiresGlobalCapture: Bool
    let accessibilityTrusted: Bool
    let flagsMonitorExpected: Bool
    let flagsMonitorActive: Bool
    let keyDownMonitorExpected: Bool
    let keyDownMonitorActive: Bool
    let keyUpMonitorExpected: Bool
    let keyUpMonitorActive: Bool
    let eventTapExpected: Bool
    let eventTapActive: Bool
    let degradationReasons: [String]

    var reasonToken: String {
        degradationReasons.isEmpty ? "none" : degradationReasons.joined(separator: ".")
    }

    var operationalSignature: String {
        [
            result.rawValue,
            Self.boolToken(requiresGlobalCapture),
            Self.boolToken(accessibilityTrusted),
            Self.boolToken(flagsMonitorExpected),
            Self.boolToken(flagsMonitorActive),
            Self.boolToken(keyDownMonitorExpected),
            Self.boolToken(keyDownMonitorActive),
            Self.boolToken(keyUpMonitorExpected),
            Self.boolToken(keyUpMonitorActive),
            Self.boolToken(eventTapExpected),
            Self.boolToken(eventTapActive),
            reasonToken
        ]
        .joined(separator: "|")
    }

    init(
        pipeline: String,
        scope: String,
        source: String,
        checkedAt: Date = Date(),
        expectation: ShortcutCaptureBackendExpectation,
        accessibilityTrusted: Bool,
        flagsMonitorActive: Bool,
        keyDownMonitorActive: Bool,
        keyUpMonitorActive: Bool,
        eventTapActive: Bool
    ) {
        let reasons = Self.computeDegradationReasons(
            expectation: expectation,
            accessibilityTrusted: accessibilityTrusted,
            flagsMonitorActive: flagsMonitorActive,
            keyDownMonitorActive: keyDownMonitorActive,
            keyUpMonitorActive: keyUpMonitorActive,
            eventTapActive: eventTapActive
        )

        self.pipeline = pipeline
        self.scope = scope
        self.source = source
        self.checkedAt = checkedAt
        requiresGlobalCapture = expectation.needsGlobalCapture
        self.accessibilityTrusted = accessibilityTrusted
        flagsMonitorExpected = expectation.needsFlagsMonitor
        self.flagsMonitorActive = flagsMonitorActive
        keyDownMonitorExpected = expectation.needsKeyDownMonitor
        self.keyDownMonitorActive = keyDownMonitorActive
        keyUpMonitorExpected = expectation.needsKeyUpMonitor
        self.keyUpMonitorActive = keyUpMonitorActive
        eventTapExpected = expectation.needsEventTap
        self.eventTapActive = eventTapActive
        degradationReasons = reasons

        if !expectation.needsGlobalCapture {
            result = .idle
        } else if reasons.isEmpty {
            result = .healthy
        } else {
            result = .degraded
        }
    }

    private static func computeDegradationReasons(
        expectation: ShortcutCaptureBackendExpectation,
        accessibilityTrusted: Bool,
        flagsMonitorActive: Bool,
        keyDownMonitorActive: Bool,
        keyUpMonitorActive: Bool,
        eventTapActive: Bool
    ) -> [String] {
        guard expectation.needsGlobalCapture else {
            return []
        }

        var reasons: [String] = []
        if !accessibilityTrusted {
            reasons.append("accessibility_denied")
        }
        if expectation.needsFlagsMonitor, !flagsMonitorActive {
            reasons.append("flags_monitor_inactive")
        }
        if expectation.needsKeyDownMonitor, !keyDownMonitorActive {
            reasons.append("key_down_monitor_inactive")
        }
        if expectation.needsKeyUpMonitor, !keyUpMonitorActive {
            reasons.append("key_up_monitor_inactive")
        }
        if expectation.needsEventTap, !eventTapActive {
            reasons.append("event_tap_inactive")
        }
        return reasons
    }

    private static func boolToken(_ value: Bool) -> String {
        value ? "1" : "0"
    }
}

import AppKit
import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure

@MainActor
final class ShortcutRecorderController: ObservableObject {
    @Published private(set) var previewLabels: [String] = []

    private var flagsMonitor: KeyboardEventMonitor?
    private var keyDownMonitor: KeyboardEventMonitor?
    private var pressedModifiers = Set<ModifierShortcutKey>()
    private var completion: ((ShortcutDefinition) -> Void)?
    private var lastModifierTap: (key: ModifierShortcutKey, date: Date)?
    private let doubleTapInterval: TimeInterval = 0.25

    func start(completion: @escaping (ShortcutDefinition) -> Void) {
        stopRecording(cancelled: true)
        self.completion = completion
        pressedModifiers.removeAll()
        previewLabels = []
        lastModifierTap = nil

        flagsMonitor = KeyboardEventMonitor(mask: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        flagsMonitor?.start()

        keyDownMonitor = KeyboardEventMonitor(mask: .keyDown, shouldReturnEvent: false) { [weak self] event in
            self?.handleKeyDown(event)
        }
        keyDownMonitor?.start()
    }

    func stopRecording(cancelled: Bool) {
        flagsMonitor?.stop()
        flagsMonitor = nil
        keyDownMonitor?.stop()
        keyDownMonitor = nil

        if cancelled {
            completion = nil
        }

        pressedModifiers.removeAll()
        lastModifierTap = nil
        previewLabels = []
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard let key = Self.modifierKey(for: event.keyCode) else {
            return
        }

        let wasPressed = pressedModifiers.contains(key)
        if wasPressed {
            pressedModifiers.remove(key)
        } else {
            pressedModifiers.insert(key)
            handleModifierPress(key)
        }

        updatePreviewFromCurrentState()
    }

    private func handleModifierPress(_ key: ModifierShortcutKey) {
        guard pressedModifiers.count == 1 else {
            lastModifierTap = nil
            return
        }

        let now = Date()
        if let lastModifierTap,
           lastModifierTap.key == key,
           now.timeIntervalSince(lastModifierTap.date) <= doubleTapInterval
        {
            commit(
                ShortcutDefinition(
                    modifiers: [key],
                    primaryKey: nil,
                    trigger: .doubleTap
                )
            )
            return
        }

        lastModifierTap = (key, now)
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard !event.isARepeat else {
            return
        }

        if event.keyCode == ShortcutKeyCode.escape {
            stopRecording(cancelled: true)
            return
        }

        if Self.modifierKey(for: event.keyCode) != nil {
            return
        }

        guard let primaryKey = Self.primaryKey(for: event) else {
            return
        }

        if pressedModifiers.isEmpty, primaryKey.kind != .function {
            return
        }

        let simpleModifiers = canonicalSimpleOrIntermediateModifiers(Array(pressedModifiers))
        let definition = ShortcutDefinition(
            modifiers: simpleModifiers,
            primaryKey: primaryKey,
            trigger: .singleTap
        )
        commit(definition)
    }

    private func commit(_ definition: ShortcutDefinition) {
        guard definition.isValid else {
            return
        }

        let completionHandler = completion
        completion = nil
        stopRecording(cancelled: true)
        previewLabels = displayLabels(for: definition)
        completionHandler?(definition)
    }

    private func updatePreviewFromCurrentState() {
        let sorted = pressedModifiers.sorted { lhs, rhs in
            lhs.sortOrder < rhs.sortOrder
        }
        previewLabels = sorted.map { $0.tokenLabel(in: sorted) }
    }

    private func displayLabels(for definition: ShortcutDefinition) -> [String] {
        var labels = definition.modifiers.map { $0.tokenLabel(in: definition.modifiers) }
        if let primaryKey = definition.primaryKey {
            labels.append(primaryKey.display)
        } else if definition.trigger == .doubleTap, labels.count == 1 {
            labels.append(labels[0])
        }
        return labels
    }

    private func canonicalSimpleOrIntermediateModifiers(_ modifiers: [ModifierShortcutKey]) -> [ModifierShortcutKey] {
        let mapped = modifiers.map { key -> ModifierShortcutKey in
            switch key {
            case .leftCommand, .rightCommand, .command:
                .command
            case .leftShift, .rightShift, .shift:
                .shift
            case .leftOption, .rightOption, .option:
                .option
            case .leftControl, .rightControl, .control:
                .control
            case .fn:
                .fn
            }
        }

        return Array(Set(mapped))
            .sorted { lhs, rhs in
                lhs.sortOrder < rhs.sortOrder
            }
    }

    private static func primaryKey(for event: NSEvent) -> ShortcutPrimaryKey? {
        if let functionIndex = ShortcutKeyCode.functionKeyByCode[event.keyCode] {
            return .function(index: functionIndex, keyCode: event.keyCode)
        }

        if event.keyCode == ShortcutKeyCode.space {
            return .space(keyCode: event.keyCode)
        }

        guard let characters = event.charactersIgnoringModifiers,
              let scalar = characters.unicodeScalars.first
        else {
            return nil
        }

        let display = String(scalar)
        if scalar.properties.isAlphabetic {
            return .letter(display, keyCode: event.keyCode)
        }

        if scalar.properties.numericType != nil {
            return .digit(display, keyCode: event.keyCode)
        }

        return .symbol(display, keyCode: event.keyCode)
    }

    private static func modifierKey(for keyCode: UInt16) -> ModifierShortcutKey? {
        switch keyCode {
        case ShortcutKeyCode.leftCommand: .leftCommand
        case ShortcutKeyCode.rightCommand: .rightCommand
        case ShortcutKeyCode.leftShift: .leftShift
        case ShortcutKeyCode.rightShift: .rightShift
        case ShortcutKeyCode.leftOption: .leftOption
        case ShortcutKeyCode.rightOption: .rightOption
        case ShortcutKeyCode.leftControl: .leftControl
        case ShortcutKeyCode.rightControl: .rightControl
        case ShortcutKeyCode.fn: .fn
        default: nil
        }
    }
}

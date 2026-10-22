import Foundation

/// Modifier keys supported by the hybrid shortcut engine.
public enum ModifierShortcutKey: String, CaseIterable, Codable, Hashable, Sendable {
    case leftCommand
    case rightCommand
    case leftShift
    case rightShift
    case leftOption
    case rightOption
    case leftControl
    case rightControl
    case fn

    /// Side-agnostic compatibility keys used only for legacy preset migration/comparison.
    case command
    case shift
    case option
    case control

    public var sortOrder: Int {
        switch self {
        case .leftCommand: 0
        case .rightCommand: 1
        case .leftShift: 2
        case .rightShift: 3
        case .leftOption: 4
        case .rightOption: 5
        case .leftControl: 6
        case .rightControl: 7
        case .fn: 8
        case .command: 9
        case .shift: 10
        case .option: 11
        case .control: 12
        }
    }
}

/// How a modifier shortcut gesture should trigger the action.
public enum ModifierShortcutTriggerMode: String, CaseIterable, Codable, Sendable {
    case singleTap
    case hold
    case doubleTap
}

/// Persistable representation of a modifier-based shortcut gesture.
public struct ModifierShortcutGesture: Codable, Equatable, Hashable, Sendable {
    public private(set) var keys: [ModifierShortcutKey]
    public var triggerMode: ModifierShortcutTriggerMode

    public init(
        keys: [ModifierShortcutKey],
        triggerMode: ModifierShortcutTriggerMode
    ) {
        self.keys = Self.normalizedKeys(keys)
        self.triggerMode = triggerMode
    }

    public var normalizedSignature: String {
        "\(triggerMode.rawValue)|\(keys.map(\.rawValue).joined(separator: "+"))"
    }

    public var isEmpty: Bool {
        keys.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case keys
        case triggerMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedKeys = try container.decode([ModifierShortcutKey].self, forKey: .keys)
        keys = Self.normalizedKeys(decodedKeys)
        triggerMode = try container.decode(ModifierShortcutTriggerMode.self, forKey: .triggerMode)
    }

    private static func normalizedKeys(_ keys: [ModifierShortcutKey]) -> [ModifierShortcutKey] {
        Array(Set(keys))
            .sorted { lhs, rhs in
                lhs.sortOrder < rhs.sortOrder
            }
    }
}

public extension ModifierShortcutTriggerMode {
    init(activationMode: ShortcutActivationMode) {
        switch activationMode {
        case .hold:
            self = .hold
        case .doubleTap:
            self = .doubleTap
        case .toggle, .holdOrToggle:
            self = .singleTap
        }
    }

    var asShortcutActivationMode: ShortcutActivationMode {
        switch self {
        case .singleTap:
            .toggle
        case .hold:
            .hold
        case .doubleTap:
            .doubleTap
        }
    }
}

public extension PresetShortcutKey {
    /// Maps legacy presets to the modifier-gesture model for compatibility checks.
    func asLegacyModifierGesture(activationMode: ShortcutActivationMode) -> ModifierShortcutGesture? {
        let triggerMode = ModifierShortcutTriggerMode(activationMode: activationMode)

        let mappedKeys: [ModifierShortcutKey]
        switch self {
        case .rightCommand:
            mappedKeys = [.rightCommand]
        case .rightOption:
            mappedKeys = [.rightOption]
        case .rightShift:
            mappedKeys = [.rightShift]
        case .rightControl:
            mappedKeys = [.rightControl]
        case .fn:
            mappedKeys = [.fn]
        case .optionCommand:
            mappedKeys = [.option, .command]
        case .controlCommand:
            mappedKeys = [.control, .command]
        case .controlOption:
            mappedKeys = [.control, .option]
        case .shiftCommand:
            mappedKeys = [.shift, .command]
        case .optionShift:
            mappedKeys = [.option, .shift]
        case .controlShift:
            mappedKeys = [.control, .shift]
        case .notSpecified, .custom:
            return nil
        }

        return ModifierShortcutGesture(keys: mappedKeys, triggerMode: triggerMode)
    }
}

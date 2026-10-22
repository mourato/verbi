import Foundation

public enum ShortcutTrigger: String, CaseIterable, Codable, Sendable {
    case singleTap
    case hold
    case doubleTap
}

public enum ShortcutPatternType: String, Codable, Sendable {
    case simple
    case intermediate
    case advanced
}

public enum ShortcutPrimaryKeyKind: String, Codable, Sendable {
    case letter
    case digit
    case symbol
    case space
    case function
}

public struct ShortcutPrimaryKey: Codable, Equatable, Hashable, Sendable {
    public let kind: ShortcutPrimaryKeyKind
    public let keyCode: UInt16
    public let display: String
    public let functionIndex: Int?

    public init(
        kind: ShortcutPrimaryKeyKind,
        keyCode: UInt16,
        display: String,
        functionIndex: Int? = nil
    ) {
        self.kind = kind
        self.keyCode = keyCode
        self.display = display
        self.functionIndex = functionIndex
    }

    public static func letter(_ value: String, keyCode: UInt16) -> ShortcutPrimaryKey {
        ShortcutPrimaryKey(kind: .letter, keyCode: keyCode, display: value.uppercased())
    }

    public static func digit(_ value: String, keyCode: UInt16) -> ShortcutPrimaryKey {
        ShortcutPrimaryKey(kind: .digit, keyCode: keyCode, display: value)
    }

    public static func symbol(_ value: String, keyCode: UInt16) -> ShortcutPrimaryKey {
        ShortcutPrimaryKey(kind: .symbol, keyCode: keyCode, display: value)
    }

    public static func space(keyCode: UInt16 = 0x31) -> ShortcutPrimaryKey {
        ShortcutPrimaryKey(kind: .space, keyCode: keyCode, display: "Space")
    }

    public static func function(index: Int, keyCode: UInt16) -> ShortcutPrimaryKey {
        ShortcutPrimaryKey(
            kind: .function,
            keyCode: keyCode,
            display: "F\(index)",
            functionIndex: index
        )
    }

    public var normalizedToken: String {
        switch kind {
        case .function:
            "f\(functionIndex ?? 0):\(keyCode)"
        case .space:
            "space:\(keyCode)"
        default:
            "\(kind.rawValue):\(display.lowercased()):\(keyCode)"
        }
    }

    public var isValid: Bool {
        switch kind {
        case .letter:
            return display.count == 1 && display.unicodeScalars.allSatisfy(\.properties.isAlphabetic)
        case .digit:
            return display.count == 1 && display.unicodeScalars.allSatisfy { scalar in
                scalar.properties.numericType != nil
            }
        case .symbol:
            return !display.isEmpty
        case .space:
            return keyCode == 0x31
        case .function:
            guard let functionIndex else { return false }
            return (1 ... 20).contains(functionIndex)
        }
    }
}

public enum ShortcutDefinitionValidationError: Equatable, Sendable {
    case missingModifiers
    case missingPrimaryKey
    case invalidPrimaryKey
    case unsupportedTriggerForAdvanced
    case unsupportedTriggerForSimpleOrIntermediate
    case advancedRequiresSingleModifier
    case advancedRequiresSideSpecificModifier
}

public struct ShortcutDefinition: Codable, Equatable, Hashable, Sendable {
    public private(set) var modifiers: [ModifierShortcutKey]
    public var primaryKey: ShortcutPrimaryKey?
    public var trigger: ShortcutTrigger

    public init(
        modifiers: [ModifierShortcutKey],
        primaryKey: ShortcutPrimaryKey?,
        trigger: ShortcutTrigger
    ) {
        self.modifiers = Self.normalizedModifiers(modifiers)
        self.primaryKey = primaryKey
        self.trigger = trigger
    }

    public var isEmpty: Bool {
        modifiers.isEmpty && primaryKey == nil
    }

    public var patternType: ShortcutPatternType {
        if primaryKey == nil {
            return .advanced
        }
        return modifiers.count <= 1 ? .simple : .intermediate
    }

    public var allowedTriggers: [ShortcutTrigger] {
        switch patternType {
        case .simple, .intermediate:
            [.singleTap]
        case .advanced:
            [.doubleTap]
        }
    }

    public var normalizedSignature: String {
        let modifiersPart = modifiers
            .map(\.rawValue)
            .joined(separator: "+")
        let primaryPart = primaryKey?.normalizedToken ?? "none"
        return "\(trigger.rawValue)|\(modifiersPart)|\(primaryPart)"
    }

    public func validate() -> ShortcutDefinitionValidationError? {
        if let primaryKey {
            guard primaryKey.isValid else {
                return .invalidPrimaryKey
            }
        }

        switch patternType {
        case .simple, .intermediate:
            guard let primaryKey else {
                return .missingPrimaryKey
            }
            guard trigger == .singleTap else {
                return .unsupportedTriggerForSimpleOrIntermediate
            }
            if modifiers.isEmpty, primaryKey.kind != .function {
                return .missingModifiers
            }
        case .advanced:
            guard !modifiers.isEmpty else {
                return .missingModifiers
            }
            guard primaryKey == nil else {
                return .missingPrimaryKey
            }
            guard trigger == .doubleTap else {
                return .unsupportedTriggerForAdvanced
            }
            guard modifiers.count == 1 else {
                return .advancedRequiresSingleModifier
            }
            guard modifiers[0].isSideSpecificOrFn else {
                return .advancedRequiresSideSpecificModifier
            }
        }

        return nil
    }

    public var isValid: Bool {
        validate() == nil
    }

    private static func normalizedModifiers(_ modifiers: [ModifierShortcutKey]) -> [ModifierShortcutKey] {
        Array(Set(modifiers))
            .sorted { lhs, rhs in
                lhs.sortOrder < rhs.sortOrder
            }
    }
}

private extension ModifierShortcutKey {
    var isSideSpecificOrFn: Bool {
        switch self {
        case .leftCommand, .rightCommand,
             .leftShift, .rightShift,
             .leftOption, .rightOption,
             .leftControl, .rightControl,
             .fn:
            true
        case .command, .shift, .option, .control:
            false
        }
    }
}

public extension ShortcutTrigger {
    init(modifierTriggerMode: ModifierShortcutTriggerMode) {
        switch modifierTriggerMode {
        case .singleTap:
            self = .singleTap
        case .hold:
            self = .hold
        case .doubleTap:
            self = .doubleTap
        }
    }

    var asModifierTriggerMode: ModifierShortcutTriggerMode {
        switch self {
        case .singleTap:
            .singleTap
        case .hold:
            .hold
        case .doubleTap:
            .doubleTap
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

public extension ModifierShortcutGesture {
    var asShortcutDefinition: ShortcutDefinition {
        ShortcutDefinition(
            modifiers: keys,
            primaryKey: nil,
            trigger: ShortcutTrigger(modifierTriggerMode: triggerMode)
        )
    }
}

public extension ShortcutDefinition {
    var asModifierShortcutGesture: ModifierShortcutGesture? {
        guard primaryKey == nil else {
            return nil
        }
        return ModifierShortcutGesture(keys: modifiers, triggerMode: trigger.asModifierTriggerMode)
    }
}

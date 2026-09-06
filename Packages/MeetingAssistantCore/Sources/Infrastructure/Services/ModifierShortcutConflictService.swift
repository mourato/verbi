import Foundation

/// Canonical action identifier used for shortcut conflict validation.
public enum ModifierShortcutActionID: Hashable, Sendable {
    case dictation
    case assistant
    case meeting
    case meetingNotes
    case cancelActiveRecording
    case systemReserved
    case assistantIntegration(UUID)

    var rawIdentifier: String {
        switch self {
        case .dictation:
            "dictation"
        case .assistant:
            "assistant"
        case .meeting:
            "meeting"
        case .meetingNotes:
            "meetingNotes"
        case .cancelActiveRecording:
            "cancelActiveRecording"
        case .systemReserved:
            "systemReserved"
        case let .assistantIntegration(id):
            "assistantIntegration.\(id.uuidString)"
        }
    }
}

/// Generic binding entry used by the conflict validator.
public struct ShortcutBinding: Equatable, Sendable {
    public let actionID: ModifierShortcutActionID
    public let actionDisplayName: String
    public let shortcut: ShortcutDefinition

    public init(
        actionID: ModifierShortcutActionID,
        actionDisplayName: String,
        shortcut: ShortcutDefinition,
    ) {
        self.actionID = actionID
        self.actionDisplayName = actionDisplayName
        self.shortcut = shortcut
    }
}

/// Binding entry used by the conflict validator for legacy modifier-only flows.
public struct ModifierShortcutBinding: Equatable, Sendable {
    public let actionID: ModifierShortcutActionID
    public let actionDisplayName: String
    public let gesture: ModifierShortcutGesture

    public init(
        actionID: ModifierShortcutActionID,
        actionDisplayName: String,
        gesture: ModifierShortcutGesture,
    ) {
        self.actionID = actionID
        self.actionDisplayName = actionDisplayName
        self.gesture = gesture
    }
}

/// Conflict result between two actions sharing the same normalized signature.
public enum ShortcutConflictReason: Equatable, Sendable {
    case identicalSignature
    case effectiveModifierOverlap
    case sideSpecificVsAgnosticOverlap
    case assistantIntegrationConcurrentActivation
    case systemReserved
    case layerLeaderKeyCollision(layerKey: String)
}

public struct ShortcutLayerBinding: Equatable, Sendable {
    public let actionID: ModifierShortcutActionID
    public let actionDisplayName: String
    public let layerKey: String

    public init(
        actionID: ModifierShortcutActionID,
        actionDisplayName: String,
        layerKey: String,
    ) {
        self.actionID = actionID
        self.actionDisplayName = actionDisplayName
        self.layerKey = layerKey
    }
}

public struct ShortcutConflictContext: Equatable, Sendable {
    public let layerBindings: [ShortcutLayerBinding]

    public init(layerBindings: [ShortcutLayerBinding] = []) {
        self.layerBindings = layerBindings
    }
}

public struct ShortcutConflict: Equatable, Sendable {
    public let candidate: ShortcutBinding
    public let conflicting: ShortcutBinding
    public let reason: ShortcutConflictReason

    public init(
        candidate: ShortcutBinding,
        conflicting: ShortcutBinding,
        reason: ShortcutConflictReason = .identicalSignature,
    ) {
        self.candidate = candidate
        self.conflicting = conflicting
        self.reason = reason
    }
}

/// Legacy compatibility alias.
public typealias ModifierShortcutConflict = ShortcutConflict

public enum ModifierShortcutConflictService {
    /// Returns the first conflict found for `candidate` against a set of `existing` bindings.
    public static func conflict(
        for candidate: ShortcutBinding,
        in existing: [ShortcutBinding],
        context: ShortcutConflictContext = ShortcutConflictContext(),
    ) -> ShortcutConflict? {
        guard !candidate.shortcut.isEmpty else {
            return nil
        }

        if let conflicting = existing.first(where: { entry in
            entry.actionID != candidate.actionID &&
                !entry.shortcut.isEmpty &&
                entry.shortcut.normalizedSignature == candidate.shortcut.normalizedSignature
        }) {
            return ShortcutConflict(
                candidate: candidate,
                conflicting: conflicting,
                reason: .identicalSignature,
            )
        }

        if let layerConflict = layerLeaderKeyConflict(for: candidate, context: context) {
            return layerConflict
        }

        guard let conflicting = existing.first(where: { entry in
            entry.actionID != candidate.actionID &&
                !entry.shortcut.isEmpty &&
                hasEquivalentActivationSemantics(candidate.shortcut, entry.shortcut) &&
                candidate.shortcut.normalizedSignature != entry.shortcut.normalizedSignature
        }) else {
            return nil
        }

        return ShortcutConflict(
            candidate: candidate,
            conflicting: conflicting,
            reason: semanticReason(candidate: candidate, conflicting: conflicting),
        )
    }

    /// Detects all duplicates in a generic bindings collection.
    public static func allConflicts(
        in bindings: [ShortcutBinding],
        context: ShortcutConflictContext = ShortcutConflictContext(),
    ) -> [ShortcutConflict] {
        var conflicts: [ShortcutConflict] = []

        for index in bindings.indices {
            let candidate = bindings[index]
            let previous = Array(bindings[..<index])
            if let conflict = conflict(for: candidate, in: previous, context: context) {
                conflicts.append(conflict)
            }
        }

        return conflicts
    }

    /// Returns the first conflict found for `candidate` against a set of `existing` modifier bindings.
    public static func conflict(
        for candidate: ModifierShortcutBinding,
        in existing: [ModifierShortcutBinding],
    ) -> ModifierShortcutConflict? {
        let genericCandidate = asShortcutBinding(candidate)
        let genericExisting = existing.map(asShortcutBinding)
        return conflict(for: genericCandidate, in: genericExisting)
    }

    /// Detects all duplicates in a modifier bindings collection.
    public static func allConflicts(in bindings: [ModifierShortcutBinding]) -> [ModifierShortcutConflict] {
        allConflicts(in: bindings.map(asShortcutBinding))
    }

    private static func asShortcutBinding(_ modifierBinding: ModifierShortcutBinding) -> ShortcutBinding {
        ShortcutBinding(
            actionID: modifierBinding.actionID,
            actionDisplayName: modifierBinding.actionDisplayName,
            shortcut: modifierBinding.gesture.asShortcutDefinition,
        )
    }

    private static let emptyShortcutPlaceholder = ShortcutDefinition(
        modifiers: [.rightCommand],
        primaryKey: nil,
        trigger: .doubleTap,
    )

    private static func semanticReason(
        candidate: ShortcutBinding,
        conflicting: ShortcutBinding,
    ) -> ShortcutConflictReason {
        if isAssistantIntegrationPair(candidate.actionID, conflicting.actionID) {
            return .assistantIntegrationConcurrentActivation
        }

        if hasSideSpecificVsAgnosticMix(
            candidate.shortcut.modifiers,
            conflicting.shortcut.modifiers,
        ) {
            return .sideSpecificVsAgnosticOverlap
        }

        return .effectiveModifierOverlap
    }

    private static func layerLeaderKeyConflict(
        for candidate: ShortcutBinding,
        context: ShortcutConflictContext,
    ) -> ShortcutConflict? {
        guard supportsLayerSemantics(candidate.actionID),
              let candidatePrimaryKey = normalizedLayerComparableKey(candidate.shortcut.primaryKey)
        else {
            return nil
        }

        guard let layerBinding = context.layerBindings.first(where: { $0.layerKey == candidatePrimaryKey }) else {
            return nil
        }

        let conflicting = ShortcutBinding(
            actionID: layerBinding.actionID,
            actionDisplayName: layerBinding.actionDisplayName,
            shortcut: emptyShortcutPlaceholder,
        )

        return ShortcutConflict(
            candidate: candidate,
            conflicting: conflicting,
            reason: .layerLeaderKeyCollision(layerKey: candidatePrimaryKey),
        )
    }

    private static func supportsLayerSemantics(_ actionID: ModifierShortcutActionID) -> Bool {
        switch actionID {
        case .assistant, .assistantIntegration:
            true
        case .dictation, .meeting, .meetingNotes, .cancelActiveRecording, .systemReserved:
            false
        }
    }

    private static func normalizedLayerComparableKey(_ primaryKey: ShortcutPrimaryKey?) -> String? {
        guard let primaryKey,
              primaryKey.kind == .letter || primaryKey.kind == .digit || primaryKey.kind == .symbol,
              primaryKey.display.count == 1,
              let character = primaryKey.display.first
        else {
            return nil
        }

        return String(character).uppercased()
    }

    private static func hasEquivalentActivationSemantics(
        _ lhs: ShortcutDefinition,
        _ rhs: ShortcutDefinition,
    ) -> Bool {
        guard lhs.trigger == rhs.trigger,
              hasEquivalentPrimaryKey(lhs.primaryKey, rhs.primaryKey)
        else {
            return false
        }

        return canModifierSetsOverlap(Set(lhs.modifiers), Set(rhs.modifiers))
    }

    private static func hasEquivalentPrimaryKey(
        _ lhs: ShortcutPrimaryKey?,
        _ rhs: ShortcutPrimaryKey?,
    ) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            true
        case let (lhs?, rhs?):
            lhs.keyCode == rhs.keyCode
        default:
            false
        }
    }

    private static func isAssistantIntegrationPair(
        _ lhs: ModifierShortcutActionID,
        _ rhs: ModifierShortcutActionID,
    ) -> Bool {
        switch (lhs, rhs) {
        case (.assistant, .assistantIntegration(_)),
             (.assistantIntegration(_), .assistant):
            true
        default:
            false
        }
    }

    private static func hasSideSpecificVsAgnosticMix(
        _ lhs: [ModifierShortcutKey],
        _ rhs: [ModifierShortcutKey],
    ) -> Bool {
        let lhsSet = Set(lhs)
        let rhsSet = Set(rhs)
        return hasSideSpecificVsAgnosticMix(
            lhsSet,
            rhsSet,
            any: .command,
            left: .leftCommand,
            right: .rightCommand,
        ) || hasSideSpecificVsAgnosticMix(
            lhsSet,
            rhsSet,
            any: .shift,
            left: .leftShift,
            right: .rightShift,
        ) || hasSideSpecificVsAgnosticMix(
            lhsSet,
            rhsSet,
            any: .option,
            left: .leftOption,
            right: .rightOption,
        ) || hasSideSpecificVsAgnosticMix(
            lhsSet,
            rhsSet,
            any: .control,
            left: .leftControl,
            right: .rightControl,
        )
    }

    private static func hasSideSpecificVsAgnosticMix(
        _ lhs: Set<ModifierShortcutKey>,
        _ rhs: Set<ModifierShortcutKey>,
        any: ModifierShortcutKey,
        left: ModifierShortcutKey,
        right: ModifierShortcutKey,
    ) -> Bool {
        let lhsIsAgnostic = lhs.contains(any)
        let rhsIsAgnostic = rhs.contains(any)
        let lhsIsSpecific = lhs.contains(left) || lhs.contains(right)
        let rhsIsSpecific = rhs.contains(left) || rhs.contains(right)
        return (lhsIsAgnostic && rhsIsSpecific) || (rhsIsAgnostic && lhsIsSpecific)
    }

    private static func canModifierSetsOverlap(
        _ lhs: Set<ModifierShortcutKey>,
        _ rhs: Set<ModifierShortcutKey>,
    ) -> Bool {
        let boolValues = [false, true]

        for leftCommand in boolValues {
            for rightCommand in boolValues {
                for leftShift in boolValues {
                    for rightShift in boolValues {
                        for leftOption in boolValues {
                            for rightOption in boolValues {
                                for leftControl in boolValues {
                                    for rightControl in boolValues {
                                        for fnIsDown in boolValues {
                                            let state = ModifierState(
                                                leftCommand: leftCommand,
                                                rightCommand: rightCommand,
                                                leftShift: leftShift,
                                                rightShift: rightShift,
                                                leftOption: leftOption,
                                                rightOption: rightOption,
                                                leftControl: leftControl,
                                                rightControl: rightControl,
                                                fnIsDown: fnIsDown,
                                            )

                                            if matchesModifierSet(lhs, state: state),
                                               matchesModifierSet(rhs, state: state)
                                            {
                                                return true
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        return false
    }

    private static func matchesModifierSet(
        _ required: Set<ModifierShortcutKey>,
        state: ModifierState,
    ) -> Bool {
        guard !required.isEmpty else {
            return false
        }

        guard matchesModifierFamily(
            required: required,
            anyFlagActive: state.leftCommand || state.rightCommand,
            leftIsDown: state.leftCommand,
            rightIsDown: state.rightCommand,
            anyKey: .command,
            leftKey: .leftCommand,
            rightKey: .rightCommand,
        ) else {
            return false
        }

        guard matchesModifierFamily(
            required: required,
            anyFlagActive: state.leftShift || state.rightShift,
            leftIsDown: state.leftShift,
            rightIsDown: state.rightShift,
            anyKey: .shift,
            leftKey: .leftShift,
            rightKey: .rightShift,
        ) else {
            return false
        }

        guard matchesModifierFamily(
            required: required,
            anyFlagActive: state.leftOption || state.rightOption,
            leftIsDown: state.leftOption,
            rightIsDown: state.rightOption,
            anyKey: .option,
            leftKey: .leftOption,
            rightKey: .rightOption,
        ) else {
            return false
        }

        guard matchesModifierFamily(
            required: required,
            anyFlagActive: state.leftControl || state.rightControl,
            leftIsDown: state.leftControl,
            rightIsDown: state.rightControl,
            anyKey: .control,
            leftKey: .leftControl,
            rightKey: .rightControl,
        ) else {
            return false
        }

        let requiresFn = required.contains(.fn)
        if requiresFn != state.fnIsDown {
            return false
        }

        return true
    }

    private static func matchesModifierFamily(
        required: Set<ModifierShortcutKey>,
        anyFlagActive: Bool,
        leftIsDown: Bool,
        rightIsDown: Bool,
        anyKey: ModifierShortcutKey,
        leftKey: ModifierShortcutKey,
        rightKey: ModifierShortcutKey,
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

    private struct ModifierState {
        let leftCommand: Bool
        let rightCommand: Bool
        let leftShift: Bool
        let rightShift: Bool
        let leftOption: Bool
        let rightOption: Bool
        let leftControl: Bool
        let rightControl: Bool
        let fnIsDown: Bool
    }
}

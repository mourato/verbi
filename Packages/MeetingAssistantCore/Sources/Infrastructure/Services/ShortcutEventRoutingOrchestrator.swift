import Foundation

public enum ShortcutEventRoutingMode: Sendable {
    case allSources
    case inHouseDefinitionOnly
}

public enum ShortcutEventRoutingOutcome: Equatable, Sendable {
    case detected(source: String, trigger: ShortcutActivationMode)
    case rejected(source: String, trigger: ShortcutActivationMode, reason: String)
    case dispatchDown(activationMode: ShortcutActivationMode)
    case dispatchUp(activationMode: ShortcutActivationMode)
}

public struct ShortcutEventRoutingSources: Equatable, Sendable {
    public let inHouseDefinition: String
    public let modifierGesture: String
    public let preset: String

    public init(
        inHouseDefinition: String,
        modifierGesture: String,
        preset: String
    ) {
        self.inHouseDefinition = inHouseDefinition
        self.modifierGesture = modifierGesture
        self.preset = preset
    }
}

public struct ShortcutEventRoutingConfiguration: Equatable, Sendable {
    public let definition: ShortcutDefinition?
    public let modifierGesture: ModifierShortcutGesture?
    public let presetKey: PresetShortcutKey
    public let presetRequiresModifierMonitoring: Bool
    public let defaultActivationMode: ShortcutActivationMode
    public let sources: ShortcutEventRoutingSources

    public init(
        definition: ShortcutDefinition?,
        modifierGesture: ModifierShortcutGesture?,
        presetKey: PresetShortcutKey,
        presetRequiresModifierMonitoring: Bool,
        defaultActivationMode: ShortcutActivationMode,
        sources: ShortcutEventRoutingSources
    ) {
        self.definition = definition
        self.modifierGesture = modifierGesture
        self.presetKey = presetKey
        self.presetRequiresModifierMonitoring = presetRequiresModifierMonitoring
        self.defaultActivationMode = defaultActivationMode
        self.sources = sources
    }
}

public struct ShortcutEventRoutingResult: Equatable, Sendable {
    public let nextPressedState: Bool?
    public let outcomes: [ShortcutEventRoutingOutcome]

    public init(nextPressedState: Bool?, outcomes: [ShortcutEventRoutingOutcome]) {
        self.nextPressedState = nextPressedState
        self.outcomes = outcomes
    }

    public static let none = ShortcutEventRoutingResult(nextPressedState: nil, outcomes: [])
}

@MainActor
public final class ShortcutEventRoutingOrchestrator {
    public typealias DefinitionActiveEvaluator = (ShortcutDefinition) -> Bool
    public typealias ModifierGestureActiveEvaluator = (ModifierShortcutGesture) -> Bool
    public typealias PresetActiveEvaluator = (PresetShortcutKey) -> Bool

    public init() {}

    public func routeMonitorEvent(
        configuration: ShortcutEventRoutingConfiguration,
        mode: ShortcutEventRoutingMode,
        wasPressed: Bool,
        isDefinitionActive: DefinitionActiveEvaluator,
        isModifierGestureActive: ModifierGestureActiveEvaluator,
        isPresetActive: PresetActiveEvaluator
    ) -> ShortcutEventRoutingResult {
        if let definition = configuration.definition {
            let isActive = isDefinitionActive(definition)
            return ShortcutEventRoutingResult(
                nextPressedState: isActive,
                outcomes: transitionOutcomes(
                    source: configuration.sources.inHouseDefinition,
                    trigger: definition.trigger.asShortcutActivationMode,
                    isActive: isActive,
                    wasPressed: wasPressed
                )
            )
        }

        if mode == .inHouseDefinitionOnly {
            return .none
        }

        if let gesture = configuration.modifierGesture {
            let isActive = isModifierGestureActive(gesture)
            return ShortcutEventRoutingResult(
                nextPressedState: isActive,
                outcomes: transitionOutcomes(
                    source: configuration.sources.modifierGesture,
                    trigger: gesture.triggerMode.asShortcutActivationMode,
                    isActive: isActive,
                    wasPressed: wasPressed
                )
            )
        }

        guard configuration.presetRequiresModifierMonitoring else {
            return .none
        }

        let isActive = isPresetActive(configuration.presetKey)
        return ShortcutEventRoutingResult(
            nextPressedState: isActive,
            outcomes: transitionOutcomes(
                source: configuration.sources.preset,
                trigger: configuration.defaultActivationMode,
                isActive: isActive,
                wasPressed: wasPressed
            )
        )
    }
}

private extension ShortcutEventRoutingOrchestrator {
    func transitionOutcomes(
        source: String,
        trigger: ShortcutActivationMode,
        isActive: Bool,
        wasPressed: Bool
    ) -> [ShortcutEventRoutingOutcome] {
        if isActive, !wasPressed {
            return [
                .detected(source: source, trigger: trigger),
                .dispatchDown(activationMode: trigger)
            ]
        }

        if !isActive, wasPressed {
            return [.dispatchUp(activationMode: trigger)]
        }

        return []
    }
}

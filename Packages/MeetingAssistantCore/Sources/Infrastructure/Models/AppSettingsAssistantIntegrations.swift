import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain

// MARK: - Assistant Integrations Configuration

public enum AssistantIntegrationPreset: String, Codable, CaseIterable, Sendable {
    case googleSearch
    case launchApps
    case closeApps
    case askChatGPT
    case askClaude
    case youtubeSearch
    case openWebsite
    case appleShortcuts
    case shellCommand
    case pressKeys

    public var localizedName: String {
        switch self {
        case .googleSearch:
            "settings.assistant.integrations.presets.google_search".localized
        case .launchApps:
            "settings.assistant.integrations.presets.launch_apps".localized
        case .closeApps:
            "settings.assistant.integrations.presets.close_apps".localized
        case .askChatGPT:
            "settings.assistant.integrations.presets.ask_chatgpt".localized
        case .askClaude:
            "settings.assistant.integrations.presets.ask_claude".localized
        case .youtubeSearch:
            "settings.assistant.integrations.presets.youtube_search".localized
        case .openWebsite:
            "settings.assistant.integrations.presets.open_website".localized
        case .appleShortcuts:
            "settings.assistant.integrations.presets.apple_shortcuts".localized
        case .shellCommand:
            "settings.assistant.integrations.presets.shell_command".localized
        case .pressKeys:
            "settings.assistant.integrations.presets.press_keys".localized
        }
    }
}

public struct AssistantIntegrationScriptConfig: Codable, Equatable, Sendable {
    public enum Stage: String, Codable, CaseIterable, Sendable {
        case beforeAI
        case afterAI

        public var localizedName: String {
            switch self {
            case .beforeAI:
                "settings.assistant.integrations.script.stage.before_ai".localized
            case .afterAI:
                "settings.assistant.integrations.script.stage.after_ai".localized
            }
        }
    }

    public var stage: Stage
    public var script: String

    public init(stage: Stage, script: String) {
        self.stage = stage
        self.script = script
    }
}

public struct AssistantIntegrationConfig: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case deeplink
    }

    public let id: UUID
    public var name: String
    public var kind: Kind
    public var isEnabled: Bool
    public var deepLink: String
    public var promptInstructions: String?
    public var selectedPreset: AssistantIntegrationPreset?
    public var shortcutDefinition: ShortcutDefinition?
    public var shortcutPresetKey: PresetShortcutKey
    public var shortcutActivationMode: ShortcutActivationMode
    public var modifierShortcutGesture: ModifierShortcutGesture?
    public var advancedScript: AssistantIntegrationScriptConfig?
    public var showsPromptSelectorInOverlay: Bool
    public var showsLanguageSelectorInOverlay: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        kind: Kind = .deeplink,
        isEnabled: Bool,
        deepLink: String,
        promptInstructions: String? = nil,
        selectedPreset: AssistantIntegrationPreset? = nil,
        shortcutDefinition: ShortcutDefinition? = nil,
        shortcutPresetKey: PresetShortcutKey = .notSpecified,
        shortcutActivationMode: ShortcutActivationMode = .holdOrToggle,
        modifierShortcutGesture: ModifierShortcutGesture? = nil,
        advancedScript: AssistantIntegrationScriptConfig? = nil,
        showsPromptSelectorInOverlay: Bool = false,
        showsLanguageSelectorInOverlay: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isEnabled = isEnabled
        self.deepLink = deepLink
        self.promptInstructions = promptInstructions
        self.selectedPreset = selectedPreset
        self.shortcutDefinition = shortcutDefinition.flatMap {
            normalizedInHouseShortcutDefinition(
                $0,
                activationMode: shortcutActivationMode,
                allowReturnOrEnter: false
            )
        }
        self.shortcutPresetKey = shortcutPresetKey
        self.shortcutActivationMode = shortcutActivationMode
        self.modifierShortcutGesture = modifierShortcutGesture
        self.advancedScript = advancedScript
        self.showsPromptSelectorInOverlay = showsPromptSelectorInOverlay
        self.showsLanguageSelectorInOverlay = showsLanguageSelectorInOverlay
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case isEnabled
        case deepLink
        case promptInstructions
        case selectedPreset
        case shortcutDefinition
        case shortcutPresetKey
        case shortcutActivationMode
        case modifierShortcutGesture
        case advancedScript
        case showsPromptSelectorInOverlay
        case showsLanguageSelectorInOverlay

        // Legacy keys kept only for backward-compatible decoding.
        case layerShortcutKey
        case leaderModeEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .deeplink
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        deepLink = try container.decodeIfPresent(String.self, forKey: .deepLink) ?? Self.defaultRaycastDeepLink

        promptInstructions = try container.decodeIfPresent(String.self, forKey: .promptInstructions)
        selectedPreset = try container.decodeIfPresent(AssistantIntegrationPreset.self, forKey: .selectedPreset)
        shortcutPresetKey = try container.decodeIfPresent(PresetShortcutKey.self, forKey: .shortcutPresetKey) ?? .notSpecified
        shortcutActivationMode = try container.decodeIfPresent(ShortcutActivationMode.self, forKey: .shortcutActivationMode) ?? .holdOrToggle
        modifierShortcutGesture = try container.decodeIfPresent(ModifierShortcutGesture.self, forKey: .modifierShortcutGesture)
        advancedScript = try container.decodeIfPresent(AssistantIntegrationScriptConfig.self, forKey: .advancedScript)
        showsPromptSelectorInOverlay = try container.decodeIfPresent(Bool.self, forKey: .showsPromptSelectorInOverlay) ?? false
        showsLanguageSelectorInOverlay = try container.decodeIfPresent(Bool.self, forKey: .showsLanguageSelectorInOverlay) ?? false

        let activationMode = shortcutActivationMode
        let modifierGesture = modifierShortcutGesture
        let presetKey = shortcutPresetKey

        let decodedShortcutDefinition = try container.decodeIfPresent(ShortcutDefinition.self, forKey: .shortcutDefinition)
        let normalizedDecodedShortcut = decodedShortcutDefinition.flatMap {
            normalizedInHouseShortcutDefinition(
                $0,
                activationMode: activationMode,
                allowReturnOrEnter: false
            )
        }
        let normalizedGestureShortcut = modifierGesture.flatMap {
            normalizedInHouseShortcutDefinition(
                $0.asShortcutDefinition,
                activationMode: activationMode,
                allowReturnOrEnter: false
            )
        }
        let normalizedLegacyShortcut = presetKey
            .asLegacyModifierGesture(activationMode: activationMode)
            .flatMap {
                normalizedInHouseShortcutDefinition(
                    $0.asShortcutDefinition,
                    activationMode: activationMode,
                    allowReturnOrEnter: false
                )
            }
        shortcutDefinition = normalizedDecodedShortcut ?? normalizedGestureShortcut ?? normalizedLegacyShortcut

        if modifierShortcutGesture == nil {
            modifierShortcutGesture = shortcutDefinition?.asModifierShortcutGesture
        }

        // Decode and ignore legacy fields to keep backward compatibility with older persisted payloads.
        _ = try container.decodeIfPresent(String.self, forKey: .layerShortcutKey)
        _ = try container.decodeIfPresent(Bool.self, forKey: .leaderModeEnabled)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(deepLink, forKey: .deepLink)
        try container.encodeIfPresent(promptInstructions, forKey: .promptInstructions)
        try container.encodeIfPresent(selectedPreset, forKey: .selectedPreset)
        try container.encodeIfPresent(shortcutDefinition, forKey: .shortcutDefinition)
        try container.encode(shortcutPresetKey, forKey: .shortcutPresetKey)
        try container.encode(shortcutActivationMode, forKey: .shortcutActivationMode)
        try container.encodeIfPresent(modifierShortcutGesture, forKey: .modifierShortcutGesture)
        try container.encodeIfPresent(advancedScript, forKey: .advancedScript)
        try container.encode(showsPromptSelectorInOverlay, forKey: .showsPromptSelectorInOverlay)
        try container.encode(showsLanguageSelectorInOverlay, forKey: .showsLanguageSelectorInOverlay)
    }

    public static var defaultRaycast: AssistantIntegrationConfig {
        AssistantIntegrationConfig(
            id: raycastDefaultID,
            name: "Raycast",
            kind: .deeplink,
            isEnabled: false,
            deepLink: defaultRaycastDeepLink,
            shortcutDefinition: defaultRaycastShortcut,
            shortcutPresetKey: .custom,
            shortcutActivationMode: .toggle
        )
    }

    private static var defaultRaycastShortcut: ShortcutDefinition {
        ShortcutDefinition(
            modifiers: [.option, .command],
            primaryKey: .letter("R", keyCode: 0x0F),
            trigger: .singleTap
        )
    }

    public static let defaultRaycastDeepLink = "raycast://extensions/raycast/raycast-ai/ai-chat"

    public static var raycastDefaultID: UUID {
        guard let uuid = UUID(uuidString: "00000000-0000-0000-0000-000000000010") else {
            assertionFailure("Invalid UUID for default Raycast integration")
            return UUID()
        }
        return uuid
    }
}

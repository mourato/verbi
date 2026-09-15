import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain

// MARK: - Sound Feedback Configuration

/// Available sounds for recording feedback notifications.
/// Uses macOS built-in system sounds. Extensible for future custom sounds.
public enum SoundFeedbackSound: String, CaseIterable, Codable, Sendable {
    case none
    // macOS System Sounds
    case glass
    case ping
    case pop
    case purr
    case submarine
    case tink
    case basso
    case blow
    case bottle
    case frog
    case funk
    case hero
    case morse
    case sosumi

    /// Localized display name for the sound.
    public var displayName: String {
        switch self {
        case .none:
            "settings.general.sound_feedback.sound.none".localized
        case .glass:
            "Glass"
        case .ping:
            "Ping"
        case .pop:
            "Pop"
        case .purr:
            "Purr"
        case .submarine:
            "Submarine"
        case .tink:
            "Tink"
        case .basso:
            "Basso"
        case .blow:
            "Blow"
        case .bottle:
            "Bottle"
        case .frog:
            "Frog"
        case .funk:
            "Funk"
        case .hero:
            "Hero"
        case .morse:
            "Morse"
        case .sosumi:
            "Sosumi"
        }
    }

    /// The macOS system sound name for NSSound.
    /// Returns nil for `.none` or custom sounds.
    public var systemSoundName: String? {
        switch self {
        case .none:
            nil
        case .glass:
            "Glass"
        case .ping:
            "Ping"
        case .pop:
            "Pop"
        case .purr:
            "Purr"
        case .submarine:
            "Submarine"
        case .tink:
            "Tink"
        case .basso:
            "Basso"
        case .blow:
            "Blow"
        case .bottle:
            "Bottle"
        case .frog:
            "Frog"
        case .funk:
            "Funk"
        case .hero:
            "Hero"
        case .morse:
            "Morse"
        case .sosumi:
            "Sosumi"
        }
    }

    /// Whether this is a system sound (vs. custom bundled sound).
    public var isSystemSound: Bool {
        self != .none
    }
}

// MARK: - Preset Shortcut Key

/// Predefined shortcut keys for quick recording activation.
/// Based on Spokenly's keyboard controls interface.
public enum PresetShortcutKey: String, CaseIterable, Codable, Sendable {
    case notSpecified
    case rightCommand
    case rightOption
    case rightShift
    case rightControl
    case optionCommand
    case controlCommand
    case controlOption
    case shiftCommand
    case optionShift
    case controlShift
    case fn
    case custom

    public var displayName: String {
        switch self {
        case .notSpecified:
            "settings.shortcuts.key.not_specified".localized
        case .rightCommand:
            "Right ⌘"
        case .rightOption:
            "Right ⌥"
        case .rightShift:
            "Right ⇧"
        case .rightControl:
            "Right ⌃"
        case .optionCommand:
            "⌥ + ⌘"
        case .controlCommand:
            "⌃ + ⌘"
        case .controlOption:
            "⌃ + ⌥"
        case .shiftCommand:
            "⇧ + ⌘"
        case .optionShift:
            "⌥ + ⇧"
        case .controlShift:
            "⌃ + ⇧"
        case .fn:
            "Fn"
        case .custom:
            "settings.shortcuts.key.custom".localized
        }
    }

    /// SF Symbol icon for the key
    public var icon: String? {
        switch self {
        case .fn: "fn"
        case .custom: "keyboard"
        default: nil
        }
    }
}

public struct AIConfiguration: Codable, Equatable, Sendable {
    public var provider: AIProvider
    public var baseURL: String
    public var selectedModel: String

    /// Legacy API key for migration purposes only.
    private var _legacyApiKey: String = ""

    public init(provider: AIProvider, baseURL: String, selectedModel: String) {
        self.provider = provider
        self.baseURL = baseURL
        self.selectedModel = selectedModel
    }

    public static let `default` = AIConfiguration(
        provider: .openai,
        baseURL: AIProvider.openai.defaultBaseURL,
        selectedModel: ""
    )

    public var isValid: Bool {
        let hasApiKey = KeychainManager.existsAPIKey(for: provider)
        return hasApiKey && !baseURL.isEmpty
    }

    /// Returns a copy of the configuration with the legacy key cleared.
    public var withoutLegacyKey: AIConfiguration {
        var copy = self
        copy._legacyApiKey = ""
        return copy
    }

    /// Internal accessor for migration logic.
    var legacyApiKey: String {
        _legacyApiKey
    }

    enum CodingKeys: String, CodingKey {
        case provider, baseURL, selectedModel
        case _legacyApiKey = "apiKey"
    }
}

public struct EnhancementsAISelection: Codable, Equatable, Hashable, Sendable {
    public var provider: AIProvider
    public var selectedModel: String
    public var registrationID: UUID?

    public init(provider: AIProvider, selectedModel: String, registrationID: UUID? = nil) {
        self.provider = provider
        self.selectedModel = selectedModel
        self.registrationID = registrationID
    }

    public static let `default` = EnhancementsAISelection(
        provider: .openai,
        selectedModel: "",
        registrationID: nil
    )

    enum CodingKeys: String, CodingKey {
        case provider
        case selectedModel
        case registrationID
    }
}

public struct EnhancementsProviderRegistration: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var provider: AIProvider
    public var displayName: String
    public var baseURLOverride: String?
    public var iconSystemName: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        provider: AIProvider,
        displayName: String,
        baseURLOverride: String? = nil,
        iconSystemName: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.baseURLOverride = baseURLOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.iconSystemName = iconSystemName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        normalizeInPlace()
    }

    public var resolvedBaseURL: String {
        switch provider {
        case .custom:
            baseURLOverride ?? ""
        case .openai, .anthropic, .groq, .google:
            provider.defaultBaseURL
        }
    }

    public var isBuiltInSingleton: Bool {
        provider != .custom
    }

    public mutating func touchUpdatedAt(_ now: Date = Date()) {
        updatedAt = now
        normalizeInPlace()
    }

    public mutating func normalizeInPlace() {
        displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if displayName.isEmpty {
            displayName = provider.displayName
        }

        if provider == .custom {
            let trimmedBaseURL = baseURLOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
            baseURLOverride = trimmedBaseURL?.isEmpty == true ? nil : trimmedBaseURL

            let trimmedIconSystemName = iconSystemName?.trimmingCharacters(in: .whitespacesAndNewlines)
            iconSystemName = trimmedIconSystemName?.isEmpty == true ? nil : trimmedIconSystemName
        } else {
            baseURLOverride = nil
            iconSystemName = nil
        }
    }
}

public extension AIProvider {
    var usesRegistrationScopedEnhancementsCredential: Bool {
        self == .custom
    }
}

public enum LocalTranscriptionModel: String, CaseIterable, Codable, Sendable {
    case parakeetTdt06BV3 = "parakeet-tdt-0.6b-v3-coreml"

    public var supportsDiarization: Bool {
        true
    }

    public var supportsIncrementalTranscription: Bool {
        true
    }

    public var displayName: String {
        "settings.service.transcription_provider.model_option.local.parakeet".localized
    }
}

public enum TranscriptionInputLanguageHint: String, CaseIterable, Codable, Sendable {
    case automatic
    case german = "de"
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case italian = "it"
    case portuguese = "pt"
    case greek = "el"
    case dutch = "nl"
    case polish = "pl"

    public var languageCode: String? {
        switch self {
        case .automatic:
            nil
        case .german, .english, .spanish, .french, .italian, .portuguese,
             .greek, .dutch, .polish:
            rawValue
        }
    }

    public var displayName: String {
        switch self {
        case .automatic:
            "settings.service.transcription_provider.input_language.option.auto".localized
        case .german:
            "settings.rules_per_app.language.option.german".localized
        case .english:
            "settings.rules_per_app.language.option.english".localized
        case .spanish:
            "settings.rules_per_app.language.option.spanish".localized
        case .french:
            "settings.rules_per_app.language.option.french".localized
        case .italian:
            "settings.rules_per_app.language.option.italian".localized
        case .portuguese:
            "settings.rules_per_app.language.option.portuguese".localized
        case .greek:
            "settings.rules_per_app.language.option.greek".localized
        case .dutch:
            "settings.rules_per_app.language.option.dutch".localized
        case .polish:
            "settings.rules_per_app.language.option.polish".localized
        }
    }
}

public enum TranscriptionProvider: String, CaseIterable, Codable, Sendable {
    case local
    case groq
    case elevenLabs

    public static let localModelID = LocalTranscriptionModel.parakeetTdt06BV3.rawValue

    public static let localPresetModelIDs = LocalTranscriptionModel.allCases.map(\.rawValue)

    public static let groqPresetModelIDs = [
        "whisper-large-v3-turbo",
        "whisper-large-v3"
    ]

    public static let elevenLabsPresetModelIDs = [
        "scribe_v1",
        "scribe_v2"
    ]

    public var defaultModelID: String {
        switch self {
        case .local:
            Self.localModelID
        case .groq:
            Self.groqPresetModelIDs[0]
        case .elevenLabs:
            Self.elevenLabsPresetModelIDs[0]
        }
    }

    public var usesRemoteInference: Bool {
        switch self {
        case .local:
            false
        case .groq, .elevenLabs:
            true
        }
    }

    public var displayName: String {
        switch self {
        case .local:
            "settings.service.transcription_provider.option.local".localized
        case .groq:
            "settings.service.transcription_provider.option.groq".localized
        case .elevenLabs:
            "settings.service.transcription_provider.option.elevenlabs".localized
        }
    }

    public func displayName(forModelID modelID: String) -> String {
        switch self {
        case .local:
            if let localModel = LocalTranscriptionModel(rawValue: modelID) {
                return localModel.displayName
            }
            return modelID
        case .groq:
            return modelID
        case .elevenLabs:
            return switch modelID {
            case "scribe_v1":
                "settings.service.transcription_provider.model_option.elevenlabs.scribe_v1".localized
            case "scribe_v2":
                "settings.service.transcription_provider.model_option.elevenlabs.scribe_v2".localized
            default:
                modelID
            }
        }
    }

    public func normalizedModelID(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return defaultModelID
        }

        if self == .local {
            return LocalTranscriptionModel(rawValue: trimmed)?.rawValue ?? Self.localModelID
        }

        return trimmed
    }
}

public enum TranscriptionExecutionMode: String, Codable, Sendable {
    case meeting
    case dictation
    case assistant
}

public extension CapturePurpose {
    var transcriptionExecutionMode: TranscriptionExecutionMode {
        self == .dictation ? .dictation : .meeting
    }
}

public struct TranscriptionProviderSelection: Codable, Equatable, Sendable {
    public var provider: TranscriptionProvider
    public var selectedModel: String

    public init(provider: TranscriptionProvider, selectedModel: String) {
        self.provider = provider
        self.selectedModel = selectedModel
    }

    public static let `default` = TranscriptionProviderSelection(
        provider: .local,
        selectedModel: TranscriptionProvider.localModelID
    )
}

public enum EnhancementsInferenceReadinessIssue: String, Sendable {
    case invalidBaseURL = "enhancements.invalid_base_url"
    case missingAPIKey = "enhancements.missing_api_key"
    case missingModel = "enhancements.missing_model"
}

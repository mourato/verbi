import Foundation
import MeetingAssistantCoreCommon

public enum DictationOutputLanguage: String, CaseIterable, Codable, Hashable, Sendable {
    case original
    case english
    case spanish
    case portuguese
    case french
    case german
    case chinese
    case japanese
    case korean
    case italian
    case hindi
    case arabic

    public var flagEmoji: String {
        switch self {
        case .original:
            "🌐"
        case .english:
            "🇬🇧"
        case .spanish:
            "🇪🇸"
        case .portuguese:
            "🇧🇷"
        case .french:
            "🇫🇷"
        case .german:
            "🇩🇪"
        case .chinese:
            "🇨🇳"
        case .japanese:
            "🇯🇵"
        case .korean:
            "🇰🇷"
        case .italian:
            "🇮🇹"
        case .hindi:
            "🇮🇳"
        case .arabic:
            "🇸🇦"
        }
    }

    public var localizedName: String {
        switch self {
        case .original:
            "settings.rules_per_app.language.option.original".localized
        case .english:
            "settings.rules_per_app.language.option.english".localized
        case .spanish:
            "settings.rules_per_app.language.option.spanish".localized
        case .portuguese:
            "settings.rules_per_app.language.option.portuguese".localized
        case .french:
            "settings.rules_per_app.language.option.french".localized
        case .german:
            "settings.rules_per_app.language.option.german".localized
        case .chinese:
            "settings.rules_per_app.language.option.chinese".localized
        case .japanese:
            "settings.rules_per_app.language.option.japanese".localized
        case .korean:
            "settings.rules_per_app.language.option.korean".localized
        case .italian:
            "settings.rules_per_app.language.option.italian".localized
        case .hindi:
            "settings.rules_per_app.language.option.hindi".localized
        case .arabic:
            "settings.rules_per_app.language.option.arabic".localized
        }
    }

    public var displayName: String {
        "\(flagEmoji) \(localizedName)"
    }

    public var instructionDisplayName: String {
        switch self {
        case .original:
            "Original language"
        case .english:
            "English"
        case .spanish:
            "Spanish"
        case .portuguese:
            "Portuguese"
        case .french:
            "French"
        case .german:
            "German"
        case .chinese:
            "Chinese"
        case .japanese:
            "Japanese"
        case .korean:
            "Korean"
        case .italian:
            "Italian"
        case .hindi:
            "Hindi"
        case .arabic:
            "Arabic"
        }
    }
}

public struct DictationAppRule: Identifiable, Codable, Hashable, Sendable {
    public let bundleIdentifier: String
    public var forceMarkdownOutput: Bool
    public var outputLanguage: DictationOutputLanguage
    public var customPromptInstructions: String?

    public init(
        bundleIdentifier: String,
        forceMarkdownOutput: Bool = true,
        outputLanguage: DictationOutputLanguage = .original,
        customPromptInstructions: String? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.forceMarkdownOutput = forceMarkdownOutput
        self.outputLanguage = outputLanguage
        self.customPromptInstructions = customPromptInstructions?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var id: String {
        bundleIdentifier
    }
}

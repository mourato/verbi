import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure
import SwiftUI

/// Visual identity of a model family or provider, rendered by `BrandAvatar`.
enum ModelBrand: Hashable {
    case openai
    case anthropic
    case google
    case groq
    case elevenLabs
    case nvidia

    var logoAssetName: String {
        switch self {
        case .openai: "openai"
        case .anthropic: "anthropic"
        case .google: "google"
        case .groq: "groq"
        case .elevenLabs: "elevenlabs"
        case .nvidia: "nvidia"
        }
    }

    var logoBackgroundColor: Color {
        switch self {
        case .openai, .elevenLabs:
            .black
        case .anthropic:
            Color(red: 242.0 / 255.0, green: 237.0 / 255.0, blue: 229.0 / 255.0)
        case .groq:
            Color(red: 232.0 / 255.0, green: 80.0 / 255.0, blue: 53.0 / 255.0)
        case .google:
            .white
        case .nvidia:
            Color(red: 118.0 / 255.0, green: 185.0 / 255.0, blue: 0.0 / 255.0)
        }
    }

    /// Tint for monochrome logos; `nil` keeps the logo's original colors.
    var logoTintColor: Color? {
        switch self {
        case .openai, .groq, .elevenLabs, .nvidia:
            .white
        case .anthropic, .google:
            nil
        }
    }
}

extension AIProvider {
    var brand: ModelBrand? {
        switch self {
        case .openai: .openai
        case .anthropic: .anthropic
        case .groq: .groq
        case .google: .google
        case .custom: nil
        }
    }
}

extension ModelBrand {
    /// Brand of the model family behind a model ID, independent of who hosts it.
    static func family(forModelID modelID: String) -> ModelBrand? {
        let id = modelID.lowercased()
        if id.contains("whisper") || id.hasPrefix("gpt-") {
            return .openai
        }
        if id.contains("parakeet") {
            return .nvidia
        }
        if id.contains("scribe") {
            return .elevenLabs
        }
        return nil
    }
}

extension TranscriptionProvider {
    /// Hosting provider brand; `nil` for on-device inference.
    var brand: ModelBrand? {
        switch self {
        case .local: nil
        case .groq: .groq
        case .elevenLabs: .elevenLabs
        case .openai: .openai
        }
    }
}

import SwiftUI
import VerbiCoreCommon
import VerbiCoreInfrastructure

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

    var logoTintColor: Color? {
        switch self {
        case .openai, .groq, .elevenLabs, .nvidia:
            .white
        case .anthropic, .google:
            nil
        }
    }
}

extension LLMProvider {
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
    private static let familyMarkers: [(fragment: String, brand: ModelBrand)] = [
        ("whisper", .openai),
        ("gpt-", .openai),
        ("parakeet", .nvidia),
        ("scribe", .elevenLabs),
        ("claude", .anthropic),
        ("gemini", .google)
    ]

    static func family(forModelID modelID: String) -> ModelBrand? {
        let id = modelID.lowercased()
        return familyMarkers.first { id.contains($0.fragment) }?.brand
    }

    static func identity(
        for provider: TranscriptionProvider,
        modelID: String
    ) -> (brand: ModelBrand?, host: ModelBrand?) {
        resolve(family: family(forModelID: modelID), host: provider.brand)
    }

    static func identity(for provider: LLMProvider, modelID: String) -> (brand: ModelBrand?, host: ModelBrand?) {
        resolve(family: family(forModelID: modelID), host: provider.brand)
    }

    private static func resolve(family: ModelBrand?, host: ModelBrand?) -> (brand: ModelBrand?, host: ModelBrand?) {
        let brand = family ?? host
        return (brand, host == brand ? nil : host)
    }
}

extension TranscriptionProvider {
    var brand: ModelBrand? {
        switch self {
        case .local: nil
        case .groq: .groq
        case .elevenLabs: .elevenLabs
        case .openai: .openai
        }
    }
}

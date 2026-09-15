import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure
import SwiftUI

extension AIProvider {
    var logoAssetName: String? {
        switch self {
        case .openai:
            "openai"
        case .anthropic:
            "anthropic"
        case .groq:
            "groq"
        case .google:
            "google"
        case .custom:
            nil
        }
    }

    var logoBackgroundColor: Color {
        switch self {
        case .openai:
            Color(
                red: 0.0 / 255.0,
                green: 0.0 / 255.0,
                blue: 0.0 / 255.0
            )
        case .anthropic:
            Color(
                red: 242.0 / 255.0,
                green: 237.0 / 255.0,
                blue: 229.0 / 255.0
            )
        case .groq:
            Color(
                red: 232.0 / 255.0,
                green: 80.0 / 255.0,
                blue: 53.0 / 255.0
            )
        case .google:
            Color.white
        case .custom:
            AppDesignSystem.Colors.subtleFill2
        }
    }

    var logoTintColor: Color? {
        switch self {
        case .openai, .groq:
            .white
        case .anthropic, .google, .custom:
            nil
        }
    }
}

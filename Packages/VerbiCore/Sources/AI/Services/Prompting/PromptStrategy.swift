import Foundation
import VerbiCoreDomain

public protocol PromptStrategy: Sendable {
    var systemPrompt: String { get }

    func userPrompt(for transcription: String) -> String

    func promptObject() -> PostProcessingPrompt
}

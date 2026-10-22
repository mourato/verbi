import Foundation
import VerbiCoreDomain

/// Defines a strategy for generating AI prompts based on meeting context.
public protocol PromptStrategy: Sendable {
    /// The system prompt to set the AI persona and constraints.
    var systemPrompt: String { get }

    /// Generates the user prompt based on the transcription text.
    /// - Parameter transcription: The raw text of the meeting transcription.
    /// - Returns: The formatted user prompt.
    func userPrompt(for transcription: String) -> String

    /// Creates a PostProcessingPrompt configuration object.
    /// - Returns: A configured PostProcessingPrompt.
    func promptObject() -> PostProcessingPrompt
}

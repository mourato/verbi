import Foundation
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

/// Infrastructure adapter for FluidAudio local transcription.
public final class FluidAIProvider: AIInfrastructureProvider, Sendable {
    public let providerName: String = "FluidAudio (Local)"

    /// We use a non-isolated task to access the MainActor-isolated client
    private let client: @MainActor () -> LocalTranscriptionClient

    public init() {
        client = { @MainActor in LocalTranscriptionClient.shared }
    }

    public func healthCheck() async throws -> Bool {
        await MainActor.run {
            let manager = FluidAIModelManager.shared
            return manager.modelState != .error
        }
    }

    public func transcribe(audioURL: URL, language: String?) async throws -> AITranscriptionResult {
        let response: TranscriptionResponse = try await LocalTranscriptionClient.shared.transcribe(
            audioURL: audioURL,
            inputLanguageHintCode: language
        )

        return AITranscriptionResult(
            text: response.text,
            language: response.language,
            durationSeconds: response.durationSeconds,
            segments: response.segments.map { segment in
                AITranscriptionSegment(
                    speaker: segment.speaker,
                    text: segment.text,
                    startTime: segment.startTime,
                    endTime: segment.endTime
                )
            },
            model: response.model
        )
    }

    public func processText(_: String, prompt _: String) throws -> String {
        // Placeholder for local LLM processing if added in the future
        // For now, this could be handled by a different provider (e.g. OpenAI)
        throw NetworkError.invalidURL // Or a more specific AI error
    }
}

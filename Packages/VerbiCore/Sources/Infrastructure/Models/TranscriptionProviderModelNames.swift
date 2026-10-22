import VerbiCoreCommon

extension TranscriptionProvider {
    /// Product name for a model ID hosted by this provider; unknown IDs fall back to the raw ID.
    public func displayName(forModelID modelID: String) -> String {
        if self == .local {
            return LocalTranscriptionModel(rawValue: modelID)?.displayName ?? modelID
        }
        return Self.cloudModelDisplayNameKeys[self]?[modelID]?.localized ?? modelID
    }

    private static let cloudModelDisplayNameKeys: [TranscriptionProvider: [String: String]] = [
        .groq: [
            "whisper-large-v3-turbo": "settings.service.transcription_provider.model_option.whisper_large_v3_turbo",
            "whisper-large-v3": "settings.service.transcription_provider.model_option.whisper_large_v3"
        ],
        .openai: [
            "gpt-4o-transcribe": "settings.service.transcription_provider.model_option.gpt_4o_transcribe",
            "gpt-4o-mini-transcribe": "settings.service.transcription_provider.model_option.gpt_4o_mini_transcribe"
        ],
        .elevenLabs: [
            "scribe_v1": "settings.service.transcription_provider.model_option.elevenlabs.scribe_v1",
            "scribe_v2": "settings.service.transcription_provider.model_option.elevenlabs.scribe_v2"
        ]
    ]
}

import MeetingAssistantCoreCommon

extension TranscriptionProvider {
    public func displayName(forModelID modelID: String) -> String {
        switch self {
        case .local:
            if let localModel = LocalTranscriptionModel(rawValue: modelID) {
                return localModel.displayName
            }
            return modelID
        case .groq, .openai, .elevenLabs:
            guard let key = Self.cloudModelDisplayNameKeys[modelID] else {
                return modelID
            }
            return key.localized
        }
    }

    private static let cloudModelDisplayNameKeys = [
        "whisper-large-v3-turbo": "settings.service.transcription_provider.model_option.whisper_large_v3_turbo",
        "whisper-large-v3": "settings.service.transcription_provider.model_option.whisper_large_v3",
        "gpt-4o-transcribe": "settings.service.transcription_provider.model_option.gpt_4o_transcribe",
        "gpt-4o-mini-transcribe": "settings.service.transcription_provider.model_option.gpt_4o_mini_transcribe",
        "scribe_v1": "settings.service.transcription_provider.model_option.elevenlabs.scribe_v1",
        "scribe_v2": "settings.service.transcription_provider.model_option.elevenlabs.scribe_v2"
    ]
}

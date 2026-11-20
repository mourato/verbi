import Foundation
import VerbiCoreDomain
import VerbiCoreInfrastructure

extension TranscriptionClient {
    /// Transcribes one closed VAD speech window through a remote provider.
    ///
    /// Windows are encoded to short in-memory WAV files so the existing
    /// file-based adapters (and their vocabulary wiring) are reused
    /// unchanged. The temporary file is removed before returning.
    func transcribeRemoteWindowSamples(
        samples: [Float],
        selection: TranscriptionProviderSelection,
        inputLanguageCode: String?,
        vocabularyHints: VocabularyProviderHints?
    ) async throws -> TranscriptionResponse {
        guard !samples.isEmpty else {
            throw TranscriptionError.transcriptionFailed("Empty speech window")
        }
        let windowURL = try RemoteWindowAudioSupport.writeTemporaryWAV(samples: samples)
        defer { try? FileManager.default.removeItem(at: windowURL) }

        let helperHints = vocabularyHints?.selecting(parameter: selection.provider.vocabularyHelper)
        switch selection.provider {
        case .local:
            throw TranscriptionError.transcriptionFailed("Local windows use the on-device path")
        case .groq:
            return try await transcribeViaGroq(
                audioURL: windowURL,
                modelID: selection.selectedModel,
                onProgress: nil,
                inputLanguageCode: inputLanguageCode,
                vocabularyHint: helperHints?.groqPrompt
            )
        case .elevenLabs:
            return try await transcribeViaElevenLabs(
                audioURL: windowURL,
                modelID: selection.selectedModel,
                onProgress: nil,
                inputLanguageCode: inputLanguageCode,
                vocabularyKeyterms: helperHints?.elevenLabsKeyterms ?? []
            )
        case .openai:
            return try await transcribeViaOpenAI(
                audioURL: windowURL,
                modelID: selection.selectedModel,
                onProgress: nil,
                inputLanguageCode: inputLanguageCode,
                vocabularyHint: helperHints?.groqPrompt
            )
        }
    }
}

import Foundation
import VerbiCoreDomain
import VerbiCoreInfrastructure

extension TranscriptionClient {
    /// Transcribes one closed VAD speech window through a remote provider.
    ///
    /// WAV encoding, multipart assembly, HTTP upload, and JSON decoding all
    /// run off `@MainActor`. Every remote provider receives the encoded WAV
    /// bytes directly in memory with zero temporary files on disk.
    func transcribeRemoteWindowSamples(
        samples: [Float],
        selection: TranscriptionProviderSelection,
        inputLanguageCode: String?,
        vocabularyHints: VocabularyProviderHints?
    ) async throws -> TranscriptionResponse {
        guard !samples.isEmpty else {
            throw TranscriptionError.transcriptionFailed("Empty speech window")
        }

        let wavData = await Task.detached(priority: .userInitiated) {
            RemoteWindowAudioSupport.wavData(from: samples)
        }.value
        let helperHints = vocabularyHints?.selecting(parameter: selection.provider.vocabularyHelper)
        let elevenLabsKeyterms = helperHints?.elevenLabsKeyterms ?? []

        return try await dispatchRemoteWindowWAV(
            wavData: wavData,
            selection: selection,
            inputLanguageCode: inputLanguageCode,
            promptHint: helperHints?.groqPrompt,
            elevenLabsKeyterms: elevenLabsKeyterms
        )
    }

    private func dispatchRemoteWindowWAV(
        wavData: Data,
        selection: TranscriptionProviderSelection,
        inputLanguageCode: String?,
        promptHint: String?,
        elevenLabsKeyterms: [String]
    ) async throws -> TranscriptionResponse {
        let fileName = "dictation-window.wav"
        switch selection.provider {
        case .local:
            throw TranscriptionError.transcriptionFailed("Local windows use the on-device path")
        case .groq:
            return try await transcribeViaGroq(
                audioData: wavData,
                fileName: fileName,
                modelID: selection.selectedModel,
                onProgress: nil,
                inputLanguageCode: inputLanguageCode,
                vocabularyHint: promptHint
            )
        case .elevenLabs:
            return try await transcribeViaElevenLabs(
                audioData: wavData,
                fileName: fileName,
                modelID: selection.selectedModel,
                onProgress: nil,
                inputLanguageCode: inputLanguageCode,
                vocabularyKeyterms: elevenLabsKeyterms
            )
        case .openai:
            return try await transcribeViaOpenAI(
                audioData: wavData,
                fileName: fileName,
                modelID: selection.selectedModel,
                onProgress: nil,
                inputLanguageCode: inputLanguageCode,
                vocabularyHint: promptHint
            )
        }
    }
}

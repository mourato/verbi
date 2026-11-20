import Foundation
import VerbiCoreDomain
import VerbiCoreInfrastructure

extension TranscriptionClient {
    /// Transcribes one closed VAD speech window through a remote provider.
    ///
    /// WAV encoding (and temporary file I/O for providers without an in-memory
    /// upload path) runs off `@MainActor`. Groq receives the encoded WAV bytes
    /// directly in memory with zero temporary files on disk.
    func transcribeRemoteWindowSamples(
        samples: [Float],
        selection: TranscriptionProviderSelection,
        inputLanguageCode: String?,
        vocabularyHints: VocabularyProviderHints?
    ) async throws -> TranscriptionResponse {
        guard !samples.isEmpty else {
            throw TranscriptionError.transcriptionFailed("Empty speech window")
        }

        let helperHints = vocabularyHints?.selecting(parameter: selection.provider.vocabularyHelper)
        switch selection.provider {
        case .local:
            throw TranscriptionError.transcriptionFailed("Local windows use the on-device path")
        case .groq:
            let wavData = await Task.detached(priority: .userInitiated) {
                RemoteWindowAudioSupport.wavData(from: samples)
            }.value
            return try await transcribeViaGroq(
                audioData: wavData,
                fileName: "dictation-window.wav",
                modelID: selection.selectedModel,
                onProgress: nil,
                inputLanguageCode: inputLanguageCode,
                vocabularyHint: helperHints?.groqPrompt
            )
        case .elevenLabs:
            return try await withTemporaryWindowWAV(samples: samples) { windowURL in
                try await transcribeViaElevenLabs(
                    audioURL: windowURL,
                    modelID: selection.selectedModel,
                    onProgress: nil,
                    inputLanguageCode: inputLanguageCode,
                    vocabularyKeyterms: helperHints?.elevenLabsKeyterms ?? []
                )
            }
        case .openai:
            return try await withTemporaryWindowWAV(samples: samples) { windowURL in
                try await transcribeViaOpenAI(
                    audioURL: windowURL,
                    modelID: selection.selectedModel,
                    onProgress: nil,
                    inputLanguageCode: inputLanguageCode,
                    vocabularyHint: helperHints?.groqPrompt
                )
            }
        }
    }

    private func withTemporaryWindowWAV(
        samples: [Float],
        operation: (URL) async throws -> TranscriptionResponse
    ) async throws -> TranscriptionResponse {
        let windowURL = try await Task.detached(priority: .userInitiated) {
            try RemoteWindowAudioSupport.writeTemporaryWAV(samples: samples)
        }.value
        do {
            let response = try await operation(windowURL)
            await removeTemporaryWindowWAV(at: windowURL)
            return response
        } catch {
            await removeTemporaryWindowWAV(at: windowURL)
            throw error
        }
    }

    private func removeTemporaryWindowWAV(at url: URL) async {
        await Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: url)
        }.value
    }
}

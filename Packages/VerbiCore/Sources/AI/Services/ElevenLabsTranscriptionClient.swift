import Foundation
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

@MainActor
public final class ElevenLabsTranscriptionClient {
    public typealias APIKeyProvider = @Sendable () throws -> String?

    private let session: URLSession
    private let apiKeyProvider: APIKeyProvider

    public init(
        session: URLSession = .shared,
        apiKeyProvider: @escaping APIKeyProvider = { try KeychainManager.retrieveTranscriptionAPIKey(for: .elevenLabs) }
    ) {
        self.session = session
        self.apiKeyProvider = apiKeyProvider
    }

    /// Transcribes an audio file via ElevenLabs off `@MainActor`.
    /// `onProgress` is `@Sendable` and may be invoked from a background executor.
    public func transcribe(
        audioURL: URL,
        modelID: String,
        inputLanguageCode: String? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil,
        vocabularyKeyterms: [String] = []
    ) async throws -> TranscriptionResponse {
        let apiKey = try resolveAPIKey()
        let normalizedModelID = Self.normalizedElevenLabsModelID(modelID)
        let session = session
        return try await Task.detached(priority: .userInitiated) {
            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                throw TranscriptionError.transcriptionFailed("Audio file not found")
            }
            let fileData = try Data(contentsOf: audioURL)
            return try await Self.performTranscription(
                session: session,
                fileData: fileData,
                fileName: audioURL.lastPathComponent,
                modelID: normalizedModelID,
                inputLanguageCode: inputLanguageCode,
                apiKey: apiKey,
                onProgress: onProgress,
                vocabularyKeyterms: vocabularyKeyterms
            )
        }.value
    }

    /// Transcribes in-memory audio bytes (e.g. a closed dictation WAV window)
    /// off `@MainActor` without writing a temporary file to disk.
    public func transcribe(
        audioData: Data,
        fileName: String,
        modelID: String,
        inputLanguageCode: String? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil,
        vocabularyKeyterms: [String] = []
    ) async throws -> TranscriptionResponse {
        let apiKey = try resolveAPIKey()
        let normalizedModelID = Self.normalizedElevenLabsModelID(modelID)
        let session = session
        return try await Task.detached(priority: .userInitiated) {
            try await Self.performTranscription(
                session: session,
                fileData: audioData,
                fileName: fileName,
                modelID: normalizedModelID,
                inputLanguageCode: inputLanguageCode,
                apiKey: apiKey,
                onProgress: onProgress,
                vocabularyKeyterms: vocabularyKeyterms
            )
        }.value
    }

    private func resolveAPIKey() throws -> String {
        let apiKey = try apiKeyProvider()?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !apiKey.isEmpty else {
            throw TranscriptionError.transcriptionFailed("error.transcription.remote_missing_api_key.elevenlabs".localized)
        }

        return apiKey
    }

    // swiftlint:disable:next function_parameter_count
    private nonisolated static func performTranscription(
        session: URLSession,
        fileData: Data,
        fileName: String,
        modelID: String,
        inputLanguageCode: String?,
        apiKey: String,
        onProgress: (@Sendable (Double) -> Void)?,
        vocabularyKeyterms: [String]
    ) async throws -> TranscriptionResponse {
        let request = try buildRequest(
            fileData: fileData,
            fileName: fileName,
            modelID: modelID,
            inputLanguageCode: inputLanguageCode,
            apiKey: apiKey,
            vocabularyKeyterms: vocabularyKeyterms
        )

        onProgress?(0.1)
        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response: response, data: data)
        let parsedResponse = try parseResponse(data: data, modelID: modelID)
        onProgress?(1)
        return parsedResponse
    }

    private nonisolated static func buildRequest(
        fileData: Data,
        fileName: String,
        modelID: String,
        inputLanguageCode: String?,
        apiKey: String,
        vocabularyKeyterms: [String] = []
    ) throws -> URLRequest {
        guard let baseURL = TranscriptionProvider.elevenLabs.remoteBaseURL,
              let url = URL(string: baseURL + "/v1/speech-to-text")
        else {
            throw TranscriptionError.transcriptionFailed("Invalid ElevenLabs transcription URL")
        }

        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = multipartBody(
            boundary: boundary,
            fileData: fileData,
            fileName: fileName,
            modelID: modelID,
            inputLanguageCode: inputLanguageCode,
            vocabularyKeyterms: vocabularyKeyterms
        )

        return request
    }

    private nonisolated static func normalizedElevenLabsModelID(_ modelID: String) -> String {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return VerbiCoreInfrastructure.TranscriptionProvider.elevenLabsPresetModelIDs[0]
        }
        return trimmed
    }

    /// Builds the multipart STT body. Internal for `@testable` request-shape assertions.
    /// Official docs (2026-07-16): repeated `keyterms` form fields, max 1000 × 50 chars.
    nonisolated static func multipartBody(
        boundary: String,
        fileData: Data,
        fileName: String,
        modelID: String,
        inputLanguageCode: String?,
        vocabularyKeyterms: [String] = []
    ) -> Data {
        var body = Data()

        appendFile(
            fieldName: "file",
            fileName: fileName,
            fileData: fileData,
            boundary: boundary,
            to: &body
        )
        appendField("model_id", value: modelID, boundary: boundary, to: &body)
        appendField("temperature", value: "0.0", boundary: boundary, to: &body)
        appendField("tag_audio_events", value: "false", boundary: boundary, to: &body)

        if let inputLanguageCode = normalizedLanguageCode(inputLanguageCode) {
            appendField("language_code", value: inputLanguageCode, boundary: boundary, to: &body)
        }
        for keyterm in VocabularyProviderHints.capElevenLabsKeyterms(vocabularyKeyterms) {
            appendField("keyterms", value: keyterm, boundary: boundary, to: &body)
        }

        appendString("--\(boundary)--\r\n", to: &body)
        return body
    }

    private nonisolated static func appendField(
        _ name: String,
        value: String,
        boundary: String,
        to body: inout Data
    ) {
        appendString("--\(boundary)\r\n", to: &body)
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n", to: &body)
        appendString("\(value)\r\n", to: &body)
    }

    private nonisolated static func appendFile(
        fieldName: String,
        fileName: String,
        fileData: Data,
        boundary: String,
        to body: inout Data
    ) {
        appendString("--\(boundary)\r\n", to: &body)
        appendString(
            "Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n",
            to: &body
        )
        appendString("Content-Type: \(mimeType(for: fileName))\r\n\r\n", to: &body)
        body.append(fileData)
        appendString("\r\n", to: &body)
    }

    private nonisolated static func appendString(_ value: String, to body: inout Data) {
        body.append(contentsOf: value.utf8)
    }

    private nonisolated static func normalizedLanguageCode(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private nonisolated static func mimeType(for fileName: String) -> String {
        switch fileName.split(separator: ".").last?.lowercased() {
        case "wav":
            "audio/wav"
        case "mp3":
            "audio/mpeg"
        case "m4a":
            "audio/mp4"
        case "aac":
            "audio/aac"
        default:
            "application/octet-stream"
        }
    }

    private nonisolated static func validateHTTPResponse(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.transcriptionFailed("Invalid ElevenLabs transcription response")
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let message = errorMessage(from: data, statusCode: httpResponse.statusCode)
            if httpResponse.statusCode == 429 {
                throw RemoteTranscriptionRateLimitError(
                    provider: "elevenLabs",
                    statusCode: 429,
                    message: message
                )
            }
            throw TranscriptionError.transcriptionFailed(message)
        }
    }

    private nonisolated static func errorMessage(from data: Data, statusCode: Int) -> String {
        if let providerError = try? JSONDecoder().decode(ElevenLabsErrorEnvelope.self, from: data) {
            return providerError.detail.status
        }
        if let rawMessage = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawMessage.isEmpty
        {
            return rawMessage
        }
        return "ElevenLabs transcription failed with status \(statusCode)"
    }

    private nonisolated static func parseResponse(data: Data, modelID: String) throws -> TranscriptionResponse {
        let decoder = JSONDecoder()
        let response = try decoder.decode(ElevenLabsTranscriptionResponse.self, from: data)

        return TranscriptionResponse(
            text: response.text,
            segments: [],
            language: response.languageCode ?? "auto",
            durationSeconds: 0,
            model: modelID,
            processedAt: ISO8601DateFormatter().string(from: Date()),
            confidenceScore: response.languageProbability
        )
    }
}

private struct ElevenLabsTranscriptionResponse: Decodable {
    let text: String
    let languageCode: String?
    let languageProbability: Double?

    enum CodingKeys: String, CodingKey {
        case text
        case languageCode = "language_code"
        case languageProbability = "language_probability"
    }
}

private struct ElevenLabsErrorEnvelope: Decodable {
    struct Detail: Decodable {
        let status: String
    }

    let detail: Detail
}

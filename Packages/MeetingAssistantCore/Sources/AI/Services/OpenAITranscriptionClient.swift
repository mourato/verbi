import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

@MainActor
public final class OpenAITranscriptionClient {
    public typealias APIKeyProvider = () throws -> String?

    private let session: URLSession
    private let apiKeyProvider: APIKeyProvider

    /// - Parameter apiKeyProvider: Reads the shared `LLMProvider.openai` Keychain slot by default.
    public init(
        session: URLSession = .shared,
        apiKeyProvider: @escaping APIKeyProvider = { try KeychainManager.retrieveAPIKey(for: .openai) }
    ) {
        self.session = session
        self.apiKeyProvider = apiKeyProvider
    }

    public func transcribe(
        audioURL: URL,
        modelID: String,
        inputLanguageCode: String? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil,
        vocabularyHint: String? = nil
    ) async throws -> TranscriptionResponse {
        let apiKey = try resolveAPIKey()
        let normalizedModel = MeetingAssistantCoreInfrastructure.TranscriptionProvider.openai.normalizedModelID(modelID)
        let request = try buildRequest(
            audioURL: audioURL,
            modelID: normalizedModel,
            inputLanguageCode: inputLanguageCode,
            apiKey: apiKey,
            vocabularyHint: vocabularyHint
        )

        onProgress?(0.1)
        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response: response, data: data)
        let parsedResponse = try parseResponse(data: data, modelID: normalizedModel)
        onProgress?(1)
        return parsedResponse
    }

    private func resolveAPIKey() throws -> String {
        let apiKey = try apiKeyProvider()?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !apiKey.isEmpty else {
            throw TranscriptionError.transcriptionFailed("error.transcription.remote_missing_api_key.openai".localized)
        }

        return apiKey
    }

    private func buildRequest(
        audioURL: URL,
        modelID: String,
        inputLanguageCode: String?,
        apiKey: String,
        vocabularyHint: String?
    ) throws -> URLRequest {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw TranscriptionError.transcriptionFailed("Audio file not found")
        }

        let endpoint = LLMProvider.openai.defaultBaseURL + "/audio/transcriptions"
        guard let url = URL(string: endpoint) else {
            throw TranscriptionError.transcriptionFailed("Invalid OpenAI transcription URL")
        }

        let fileData = try Data(contentsOf: audioURL)
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = Self.multipartBody(
            boundary: boundary,
            fileData: fileData,
            fileName: audioURL.lastPathComponent,
            modelID: modelID,
            inputLanguageCode: inputLanguageCode,
            vocabularyHint: vocabularyHint
        )

        return request
    }

    /// Builds the multipart transcription body. Internal for `@testable` request-shape assertions.
    /// `gpt-4o(-mini)-transcribe` accept only `json` or `text` response formats.
    nonisolated static func multipartBody(
        boundary: String,
        fileData: Data,
        fileName: String,
        modelID: String,
        inputLanguageCode: String?,
        vocabularyHint: String? = nil
    ) -> Data {
        var body = Data()

        appendField("model", value: modelID, boundary: boundary, to: &body)
        appendField("response_format", value: "json", boundary: boundary, to: &body)
        if let inputLanguageCode = normalizedLanguageCode(inputLanguageCode) {
            appendField("language", value: inputLanguageCode, boundary: boundary, to: &body)
        }
        if let vocabularyHint = VocabularyProviderHints.capGroqPrompt(vocabularyHint),
           !vocabularyHint.isEmpty
        {
            appendField("prompt", value: vocabularyHint, boundary: boundary, to: &body)
        }

        appendString("--\(boundary)\r\n", to: &body)
        appendString("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n", to: &body)
        appendString("Content-Type: \(mimeType(for: fileName))\r\n\r\n", to: &body)
        body.append(fileData)
        appendString("\r\n", to: &body)
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

    private func validateHTTPResponse(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.transcriptionFailed("Invalid OpenAI transcription response")
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            if let providerError = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw TranscriptionError.transcriptionFailed(providerError.error.message)
            }
            throw TranscriptionError.transcriptionFailed("OpenAI transcription failed with status \(httpResponse.statusCode)")
        }
    }

    private func parseResponse(data: Data, modelID: String) throws -> TranscriptionResponse {
        guard let response = try? JSONDecoder().decode(OpenAITranscriptionResponse.self, from: data) else {
            throw TranscriptionError.transcriptionFailed("Unexpected OpenAI transcription payload")
        }

        return TranscriptionResponse(
            text: response.text,
            segments: [],
            language: "auto",
            durationSeconds: 0,
            model: modelID,
            processedAt: ISO8601DateFormatter().string(from: Date()),
            confidenceScore: nil
        )
    }
}

private struct OpenAITranscriptionResponse: Decodable {
    let text: String
}

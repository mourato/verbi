import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

@MainActor
public final class ElevenLabsTranscriptionClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func transcribe(
        audioURL: URL,
        modelID: String,
        inputLanguageCode: String? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil,
        vocabularyKeyterms: [String] = []
    ) async throws -> TranscriptionResponse {
        let apiKey = try resolveAPIKey()
        let normalizedModelID = normalizedElevenLabsModelID(modelID)
        let request = try buildRequest(
            audioURL: audioURL,
            modelID: normalizedModelID,
            inputLanguageCode: inputLanguageCode,
            apiKey: apiKey,
            vocabularyKeyterms: vocabularyKeyterms
        )

        onProgress?(0.1)
        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response: response, data: data)
        let parsedResponse = try parseResponse(data: data, modelID: normalizedModelID)
        onProgress?(1)
        return parsedResponse
    }

    private func resolveAPIKey() throws -> String {
        let apiKey = try KeychainManager.retrieveTranscriptionAPIKey(for: .elevenLabs)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !apiKey.isEmpty else {
            throw TranscriptionError.transcriptionFailed("error.transcription.remote_missing_api_key.elevenlabs".localized)
        }

        return apiKey
    }

    private func buildRequest(
        audioURL: URL,
        modelID: String,
        inputLanguageCode: String?,
        apiKey: String,
        vocabularyKeyterms: [String] = []
    ) throws -> URLRequest {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw TranscriptionError.transcriptionFailed("Audio file not found")
        }

        guard let url = URL(string: "https://api.elevenlabs.io/v1/speech-to-text") else {
            throw TranscriptionError.transcriptionFailed("Invalid ElevenLabs transcription URL")
        }

        let fileData = try Data(contentsOf: audioURL)
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = Self.multipartBody(
            boundary: boundary,
            fileData: fileData,
            fileName: audioURL.lastPathComponent,
            modelID: modelID,
            inputLanguageCode: inputLanguageCode,
            vocabularyKeyterms: vocabularyKeyterms
        )

        return request
    }

    private func normalizedElevenLabsModelID(_ modelID: String) -> String {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return MeetingAssistantCoreInfrastructure.TranscriptionProvider.elevenLabsPresetModelIDs[0]
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

    private func validateHTTPResponse(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.transcriptionFailed("Invalid ElevenLabs transcription response")
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            if let providerError = try? JSONDecoder().decode(ElevenLabsErrorEnvelope.self, from: data) {
                throw TranscriptionError.transcriptionFailed(providerError.detail.status)
            }

            if let rawMessage = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !rawMessage.isEmpty
            {
                throw TranscriptionError.transcriptionFailed(rawMessage)
            }

            throw TranscriptionError.transcriptionFailed(
                "ElevenLabs transcription failed with status \(httpResponse.statusCode)"
            )
        }
    }

    private func parseResponse(data: Data, modelID: String) throws -> TranscriptionResponse {
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

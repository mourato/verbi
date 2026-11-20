import Foundation
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

@MainActor
public final class GroqTranscriptionClient {
    public typealias APIKeyProvider = @Sendable () throws -> String?

    private let session: URLSession
    private let apiKeyProvider: APIKeyProvider

    public init(
        session: URLSession = .shared,
        apiKeyProvider: @escaping APIKeyProvider = { try KeychainManager.retrieveAPIKey(for: .groq) }
    ) {
        self.session = session
        self.apiKeyProvider = apiKeyProvider
    }

    /// Transcribes an audio file via Groq off `@MainActor`.
    /// `onProgress` is `@Sendable` and may be invoked from a background executor.
    public func transcribe(
        audioURL: URL,
        modelID: String,
        inputLanguageCode: String? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil,
        vocabularyHint: String? = nil
    ) async throws -> TranscriptionResponse {
        let apiKey = try resolveAPIKey()
        let normalizedModel = Self.normalizedGroqModelID(modelID)
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
                modelID: normalizedModel,
                inputLanguageCode: inputLanguageCode,
                apiKey: apiKey,
                onProgress: onProgress,
                vocabularyHint: vocabularyHint
            )
        }.value
    }

    /// Transcribes in-memory audio bytes (e.g. a closed dictation WAV window)
    /// off `@MainActor` without writing a temporary file to disk.
    /// `onProgress` is `@Sendable` and may be invoked from a background executor.
    public func transcribe(
        audioData: Data,
        fileName: String,
        modelID: String,
        inputLanguageCode: String? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil,
        vocabularyHint: String? = nil
    ) async throws -> TranscriptionResponse {
        let apiKey = try resolveAPIKey()
        let normalizedModel = Self.normalizedGroqModelID(modelID)
        let session = session
        return try await Task.detached(priority: .userInitiated) {
            try await Self.performTranscription(
                session: session,
                fileData: audioData,
                fileName: fileName,
                modelID: normalizedModel,
                inputLanguageCode: inputLanguageCode,
                apiKey: apiKey,
                onProgress: onProgress,
                vocabularyHint: vocabularyHint
            )
        }.value
    }

    private func resolveAPIKey() throws -> String {
        let apiKey = try apiKeyProvider()?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !apiKey.isEmpty else {
            throw TranscriptionError.transcriptionFailed("error.transcription.remote_missing_api_key.groq".localized)
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
        vocabularyHint: String?
    ) async throws -> TranscriptionResponse {
        let request = try buildRequest(
            fileData: fileData,
            fileName: fileName,
            modelID: modelID,
            inputLanguageCode: inputLanguageCode,
            apiKey: apiKey,
            vocabularyHint: vocabularyHint
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
        vocabularyHint: String? = nil
    ) throws -> URLRequest {
        let endpoint = LLMProvider.groq.defaultBaseURL + "/audio/transcriptions"
        guard let url = URL(string: endpoint) else {
            throw TranscriptionError.transcriptionFailed("Invalid Groq transcription URL")
        }

        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = multipartBody(
            boundary: boundary,
            fileData: fileData,
            fileName: fileName,
            modelID: modelID,
            inputLanguageCode: inputLanguageCode,
            vocabularyHint: vocabularyHint
        )

        return request
    }

    private nonisolated static func normalizedGroqModelID(_ modelID: String) -> String {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "whisper-large-v3-turbo"
        }
        return trimmed
    }

    /// Builds the multipart transcription body. Internal for `@testable` request-shape assertions.
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
        appendField("response_format", value: "verbose_json", boundary: boundary, to: &body)
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

    private nonisolated static func validateHTTPResponse(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.transcriptionFailed("Invalid Groq transcription response")
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(GroqErrorEnvelope.self, from: data))?.error.message
                ?? "Groq transcription failed with status \(httpResponse.statusCode)"
            if httpResponse.statusCode == 429 {
                throw RemoteTranscriptionRateLimitError(
                    provider: "groq",
                    statusCode: 429,
                    message: message
                )
            }
            throw TranscriptionError.transcriptionFailed(message)
        }
    }

    private nonisolated static func parseResponse(data: Data, modelID: String) throws -> TranscriptionResponse {
        let decoder = JSONDecoder()

        if let verboseResponse = try? decoder.decode(GroqVerboseTranscriptionResponse.self, from: data) {
            let segments = (verboseResponse.segments ?? []).map { segment in
                CaptureArtifact.Segment(
                    speaker: CaptureArtifact.unknownSpeaker,
                    text: segment.text,
                    startTime: segment.start,
                    endTime: segment.end
                )
            }

            return TranscriptionResponse(
                text: verboseResponse.text,
                segments: segments,
                language: verboseResponse.language ?? "auto",
                durationSeconds: verboseResponse.duration ?? 0,
                model: modelID,
                processedAt: ISO8601DateFormatter().string(from: Date()),
                confidenceScore: nil
            )
        }

        if let minimalResponse = try? decoder.decode(GroqMinimalTranscriptionResponse.self, from: data) {
            return TranscriptionResponse(
                text: minimalResponse.text,
                segments: [],
                language: "auto",
                durationSeconds: 0,
                model: modelID,
                processedAt: ISO8601DateFormatter().string(from: Date()),
                confidenceScore: nil
            )
        }

        throw TranscriptionError.transcriptionFailed("Unexpected Groq transcription payload")
    }
}

private struct GroqMinimalTranscriptionResponse: Decodable {
    let text: String
}

private struct GroqVerboseTranscriptionResponse: Decodable {
    struct Segment: Decodable {
        let text: String
        let start: Double
        let end: Double
    }

    let text: String
    let language: String?
    let duration: Double?
    let segments: [Segment]?
}

private struct GroqErrorEnvelope: Decodable {
    struct ProviderError: Decodable {
        let message: String
    }

    let error: ProviderError
}

import Foundation
@testable import VerbiCoreAI
import VerbiCoreCommon
import VerbiCoreDomain
@testable import VerbiCoreInfrastructure
import XCTest

@MainActor
final class OpenAITranscriptionClientTests: XCTestCase {
    private var audioURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openai-transcription-\(UUID().uuidString).wav")
        try Data("audio".utf8).write(to: audioURL)
        OpenAITranscriptionURLProtocolStub.reset()
    }

    override func tearDown() async throws {
        OpenAITranscriptionURLProtocolStub.reset()
        try? FileManager.default.removeItem(at: audioURL)
        audioURL = nil
        try await super.tearDown()
    }

    func testOpenAIProvider_DefaultsToGPT4oTranscribeAndNormalizesLikeGroq() {
        let provider = VerbiCoreInfrastructure.TranscriptionProvider.openai

        XCTAssertEqual(provider.rawValue, "openai")
        XCTAssertEqual(
            VerbiCoreInfrastructure.TranscriptionProvider.openAIPresetModelIDs,
            ["gpt-4o-transcribe", "gpt-4o-mini-transcribe"]
        )
        XCTAssertEqual(provider.defaultModelID, "gpt-4o-transcribe")
        XCTAssertEqual(provider.normalizedModelID("  "), "gpt-4o-transcribe")
        XCTAssertEqual(provider.normalizedModelID(" gpt-4o-mini-transcribe "), "gpt-4o-mini-transcribe")
        XCTAssertTrue(provider.usesRemoteInference)
        XCTAssertEqual(provider.displayName, "settings.service.transcription_provider.option.openai".localized)
        XCTAssertEqual(
            provider.displayName(forModelID: "gpt-4o-transcribe"),
            "settings.service.transcription_provider.model_option.gpt_4o_transcribe".localized
        )
        XCTAssertEqual(provider.displayName(forModelID: "custom-model"), "custom-model")
    }

    func testMultipartBody_SendsModelJSONFormatLanguageAndFile() {
        let body = OpenAITranscriptionClient.multipartBody(
            boundary: "Bound",
            fileData: Data("audio".utf8),
            fileName: "clip.wav",
            modelID: "gpt-4o-transcribe",
            inputLanguageCode: "pt"
        )
        let text = String(bytes: body, encoding: .utf8) ?? ""

        XCTAssertTrue(text.contains("name=\"model\"\r\n\r\ngpt-4o-transcribe\r\n"))
        XCTAssertTrue(text.contains("name=\"response_format\"\r\n\r\njson\r\n"))
        XCTAssertTrue(text.contains("name=\"language\"\r\n\r\npt\r\n"))
        XCTAssertTrue(text.contains("name=\"file\"; filename=\"clip.wav\"\r\nContent-Type: audio/wav"))
        XCTAssertFalse(text.contains("verbose_json"))
        XCTAssertFalse(text.contains("name=\"prompt\""))
        XCTAssertTrue(text.hasSuffix("--Bound--\r\n"))
    }

    func testTranscriptionClient_RoutesOpenAISelectionToTranscriptionsEndpointWithSharedKey() async throws {
        OpenAITranscriptionURLProtocolStub.responseBody = Data(#"{"text":"olá mundo"}"#.utf8)
        let client = makeTranscriptionClient(apiKey: "sk-openai-test")

        let response = try await client.transcribe(
            audioURL: audioURL,
            onProgress: nil,
            executionMode: .dictation,
            diarizationEnabledOverride: nil,
            selection: TranscriptionProviderSelection(provider: .openai, selectedModel: "gpt-4o-mini-transcribe"),
            inputLanguageCode: "pt",
            vocabularyHints: nil
        )

        let request = try XCTUnwrap(OpenAITranscriptionURLProtocolStub.capturedRequests.first)
        XCTAssertEqual(OpenAITranscriptionURLProtocolStub.capturedRequests.count, 1)
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-openai-test")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        let body = String(bytes: OpenAITranscriptionURLProtocolStub.capturedBodies.first ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("name=\"model\"\r\n\r\ngpt-4o-mini-transcribe\r\n"))
        XCTAssertTrue(body.contains("name=\"language\"\r\n\r\npt\r\n"))
        XCTAssertEqual(response.text, "olá mundo")
        XCTAssertEqual(response.model, "gpt-4o-mini-transcribe")
    }

    func testTranscriptionClient_OpenAIMissingKeyThrowsLocalizedErrorWithoutNetwork() async {
        let client = makeTranscriptionClient(apiKey: "   ")

        do {
            _ = try await client.transcribe(
                audioURL: audioURL,
                onProgress: nil,
                executionMode: .dictation,
                diarizationEnabledOverride: nil,
                selection: TranscriptionProviderSelection(provider: .openai, selectedModel: "gpt-4o-transcribe"),
                inputLanguageCode: nil,
                vocabularyHints: nil
            )
            XCTFail("Expected missing OpenAI key error")
        } catch let TranscriptionError.transcriptionFailed(message) {
            XCTAssertEqual(message, "error.transcription.remote_missing_api_key.openai".localized)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(OpenAITranscriptionURLProtocolStub.capturedRequests.isEmpty)
    }

    private func makeTranscriptionClient(apiKey: String?) -> TranscriptionClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAITranscriptionURLProtocolStub.self]
        let openAIClient = OpenAITranscriptionClient(
            session: URLSession(configuration: configuration),
            apiKeyProvider: { apiKey }
        )
        return TranscriptionClient(settingsStore: .shared, openAITranscriptionClient: openAIClient)
    }
}

private final class OpenAITranscriptionURLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []
    nonisolated(unsafe) static var capturedBodies: [Data] = []
    nonisolated(unsafe) static var responseBody = Data()

    static func reset() {
        capturedRequests = []
        capturedBodies = []
        responseBody = Data()
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.capturedRequests.append(request)
        Self.capturedBodies.append(Self.bodyData(of: request))

        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func bodyData(of request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

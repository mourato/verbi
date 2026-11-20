import Foundation
@testable import VerbiCoreAI
import VerbiCoreDomain
import XCTest

@MainActor
final class GroqRemoteIncrementalClientTests: XCTestCase {
    override func tearDown() async throws {
        GroqRemoteIncrementalURLProtocolStub.reset()
        try await super.tearDown()
    }

    func testInMemoryAudioData_UploadsWithoutTempFileAndThrowsRateLimitOn429() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GroqRemoteIncrementalURLProtocolStub.self]
        let groqClient = GroqTranscriptionClient(
            session: URLSession(configuration: config),
            apiKeyProvider: { "test-groq-key" }
        )

        GroqRemoteIncrementalURLProtocolStub.statusCode = 200
        GroqRemoteIncrementalURLProtocolStub.responseBody = Data(#"{"text":"ola mundo","language":"pt","duration":1.2}"#.utf8)

        let wavData = RemoteWindowAudioSupport.wavData(from: [Float](repeating: 0.1, count: 1600))
        let response = try await groqClient.transcribe(
            audioData: wavData,
            fileName: "dictation-window.wav",
            modelID: "whisper-large-v3-turbo",
            inputLanguageCode: "pt",
            vocabularyHint: "Verbi"
        )
        XCTAssertEqual(response.text, "ola mundo")
        XCTAssertEqual(GroqRemoteIncrementalURLProtocolStub.capturedRequests.count, 1)
        let uploadedBody = GroqRemoteIncrementalURLProtocolStub.capturedBodies[0]
        XCTAssertNotNil(uploadedBody.range(of: Data("filename=\"dictation-window.wav\"".utf8)))
        XCTAssertNotNil(uploadedBody.range(of: Data("Content-Type: audio/wav".utf8)))
        XCTAssertNotNil(uploadedBody.range(of: Data("RIFF".utf8)))

        GroqRemoteIncrementalURLProtocolStub.statusCode = 429
        GroqRemoteIncrementalURLProtocolStub.responseBody = Data(#"{"error":{"message":"Quota exceeded"}}"#.utf8)

        do {
            _ = try await groqClient.transcribe(
                audioData: wavData,
                fileName: "dictation-window.wav",
                modelID: "whisper-large-v3-turbo"
            )
            XCTFail("Expected RemoteTranscriptionRateLimitError on HTTP 429")
        } catch let error as RemoteTranscriptionRateLimitError {
            XCTAssertEqual(error.statusCode, 429)
            XCTAssertEqual(error.message, "Quota exceeded")
            XCTAssertTrue(RemoteWindowAudioSupport.isRateLimited(error))
        }
    }
}

private final class GroqRemoteIncrementalURLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []
    nonisolated(unsafe) static var capturedBodies: [Data] = []
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var responseBody = Data()

    static func reset() {
        capturedRequests = []
        capturedBodies = []
        statusCode = 200
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
              let response = HTTPURLResponse(url: url, statusCode: Self.statusCode, httpVersion: nil, headerFields: nil)
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

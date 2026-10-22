import Foundation
@testable import VerbiCore
import XCTest

@MainActor
final class MeetingQAServiceTests: XCTestCase {
    private var originalMeetingQnAEnabled = false
    private var originalAIConfiguration = AIConfiguration.default
    private var originalEnhancementsAISelection = EnhancementsAISelection.default

    override func setUp() async throws {
        try await super.setUp()
        try AppSettingsTestIsolationLock.acquire()
        let settings = AppSettingsStore.shared
        originalMeetingQnAEnabled = settings.meetingQnAEnabled
        originalAIConfiguration = settings.aiConfiguration
        originalEnhancementsAISelection = settings.enhancementsAISelection

        settings.meetingQnAEnabled = true
        settings.aiConfiguration = AIConfiguration(
            provider: .openai,
            baseURL: "https://example.com/v1",
            selectedModel: "gpt-4o-mini",
        )
        settings.enhancementsAISelection = EnhancementsAISelection(
            provider: .openai,
            selectedModel: "gpt-4o-mini",
        )
    }

    override func tearDown() async throws {
        let settings = AppSettingsStore.shared
        settings.meetingQnAEnabled = originalMeetingQnAEnabled
        settings.aiConfiguration = originalAIConfiguration
        settings.enhancementsAISelection = originalEnhancementsAISelection
        MockMeetingQANetworkURLProtocol.requestHandler = nil
        AppSettingsTestIsolationLock.release()
        try await super.tearDown()
    }

    func testAskReturnsAnsweredWithEvidence() async throws {
        let session = makeMockedSession()
        MockMeetingQANetworkURLProtocol.requestHandler = { _ in
            let body = """
            {
              "choices": [
                {
                  "message": {
                    "content": "{\\\"status\\\":\\\"answered\\\",\\\"answer\\\":\\\"Launch is Friday.\\\",\\\"evidence\\\":[{\\\"speaker\\\":\\\"Ana\\\",\\\"startTime\\\":12,\\\"endTime\\\":16,\\\"excerpt\\\":\\\"Vamos lançar sexta.\\\"}]}"
                  }
                }
              ]
            }
            """
            return (
                HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8),
            )
        }

        let service = MeetingQAService(
            settings: .shared,
            apiKeyProvider: { _ in "test-key" },
            sleepFunction: { _ in },
            providerHTTPClient: ProviderHTTPClient(session: session),
        )

        let response = try await service.ask(
            question: "When are we launching?",
            transcription: makeTranscription(),
        )

        XCTAssertEqual(response.status, .answered)
        XCTAssertEqual(response.answer, "Launch is Friday.")
        XCTAssertEqual(response.evidence.count, 1)
        XCTAssertEqual(response.evidence.first?.speaker, "Ana")
    }

    func testAskReturnsNotFoundWhenAnsweredPayloadHasNoEvidence() async throws {
        let session = makeMockedSession()
        MockMeetingQANetworkURLProtocol.requestHandler = { _ in
            let body = """
            {
              "choices": [
                {
                  "message": {
                    "content": "{\\\"status\\\":\\\"answered\\\",\\\"answer\\\":\\\"This lacks evidence.\\\",\\\"evidence\\\":[]}"
                  }
                }
              ]
            }
            """
            return (
                HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8),
            )
        }

        let service = MeetingQAService(
            settings: .shared,
            apiKeyProvider: { _ in "test-key" },
            sleepFunction: { _ in },
            providerHTTPClient: ProviderHTTPClient(session: session),
        )

        let response = try await service.ask(
            question: "What did we decide?",
            transcription: makeTranscription(),
        )

        XCTAssertEqual(response.status, .notFound)
        XCTAssertTrue(response.answer.isEmpty)
        XCTAssertTrue(response.evidence.isEmpty)
    }

    func testAskRetriesOnceAfterTimeoutThenSucceeds() async throws {
        let session = makeMockedSession()
        var callCount = 0

        MockMeetingQANetworkURLProtocol.requestHandler = { _ in
            callCount += 1

            if callCount == 1 {
                throw URLError(.timedOut)
            }

            let body = """
            {
              "choices": [
                {
                  "message": {
                    "content": "{\\\"status\\\":\\\"answered\\\",\\\"answer\\\":\\\"Budget approved.\\\",\\\"evidence\\\":[{\\\"speaker\\\":\\\"João\\\",\\\"startTime\\\":30,\\\"endTime\\\":38,\\\"excerpt\\\":\\\"Fechamos o orçamento hoje.\\\"}]}"
                  }
                }
              ]
            }
            """

            return (
                HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8),
            )
        }

        let service = MeetingQAService(
            settings: .shared,
            apiKeyProvider: { _ in "test-key" },
            sleepFunction: { _ in },
            providerHTTPClient: ProviderHTTPClient(session: session),
        )

        let response = try await service.ask(
            question: "What happened with budget?",
            transcription: makeTranscription(),
        )

        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(response.status, .answered)
        XCTAssertEqual(response.answer, "Budget approved.")
    }

    func testAskFailsWhenEnhancementsModelIsMissing() async {
        let settings = AppSettingsStore.shared
        settings.enhancementsAISelection = EnhancementsAISelection(
            provider: .openai,
            selectedModel: "   ",
        )

        let service = MeetingQAService(
            settings: .shared,
            apiKeyProvider: { _ in "test-key" },
            sleepFunction: { _ in },
            providerHTTPClient: ProviderHTTPClient(session: makeMockedSession()),
        )

        do {
            _ = try await service.ask(
                question: "What did we decide?",
                transcription: makeTranscription(),
            )
            XCTFail("Expected ask to fail when selected model is missing")
        } catch let error as MeetingQAError {
            guard case .noAPIConfigured = error else {
                return XCTFail("Expected .noAPIConfigured, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testAskFailsForDictationTranscription() async {
        let service = MeetingQAService(
            settings: .shared,
            apiKeyProvider: { _ in "test-key" },
            sleepFunction: { _ in },
            providerHTTPClient: ProviderHTTPClient(session: makeMockedSession()),
        )

        do {
            _ = try await service.ask(
                question: "What did we decide?",
                transcription: makeTranscription(app: .unknown),
            )
            XCTFail("Expected ask to fail for dictation transcription")
        } catch let error as MeetingQAError {
            guard case .disabled = error else {
                return XCTFail("Expected .disabled, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testAskWithGoogleProviderParsesGeminiPayload() async throws {
        let settings = AppSettingsStore.shared
        settings.aiConfiguration = AIConfiguration(
            provider: .google,
            baseURL: LLMProvider.google.defaultBaseURL,
            selectedModel: "gemini-2.0-flash",
        )
        settings.enhancementsAISelection = EnhancementsAISelection(
            provider: .google,
            selectedModel: "gemini-2.0-flash",
        )

        let session = makeMockedSession()
        MockMeetingQANetworkURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.absoluteString.contains("models/gemini-2.0-flash:generateContent") ?? false)
            var queryItems: [URLQueryItem] = []
            if let url = request.url,
               let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            {
                queryItems = components.queryItems ?? []
            }

            var hasNonEmptyKey = false
            for item in queryItems {
                if item.name == "key", let value = item.value, !value.isEmpty {
                    hasNonEmptyKey = true
                    break
                }
            }
            XCTAssertTrue(hasNonEmptyKey)
            let body = """
            {
              "candidates": [
                {
                  "content": {
                    "parts": [
                      {
                        "text": "{\\\"status\\\":\\\"answered\\\",\\\"answer\\\":\\\"Launch is Friday.\\\",\\\"evidence\\\":[{\\\"speaker\\\":\\\"Ana\\\",\\\"startTime\\\":12,\\\"endTime\\\":16,\\\"excerpt\\\":\\\"Vamos lançar sexta.\\\"}]}"
                      }
                    ]
                  }
                }
              ]
            }
            """
            return (
                HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8),
            )
        }

        let service = MeetingQAService(
            settings: .shared,
            apiKeyProvider: { _ in "test-key" },
            sleepFunction: { _ in },
            providerHTTPClient: ProviderHTTPClient(session: session),
        )

        let response = try await service.ask(
            question: "When are we launching?",
            transcription: makeTranscription(),
        )

        XCTAssertEqual(response.status, .answered)
        XCTAssertEqual(response.answer, "Launch is Friday.")
    }

    func testAskKernelRequestUsesModelSelectionOverride() async throws {
        let session = makeMockedSession()
        MockMeetingQANetworkURLProtocol.requestHandler = { request in
            let bodyData = try XCTUnwrap(self.requestBodyData(from: request))
            let jsonObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            XCTAssertEqual(jsonObject["model"] as? String, "gpt-4.1-mini")

            let body = """
            {
              "choices": [
                {
                  "message": {
                    "content": "{\\\"status\\\":\\\"answered\\\",\\\"answer\\\":\\\"Override model used.\\\",\\\"evidence\\\":[{\\\"speaker\\\":\\\"Ana\\\",\\\"startTime\\\":12,\\\"endTime\\\":16,\\\"excerpt\\\":\\\"Vamos lançar sexta.\\\"}]}"
                  }
                }
              ]
            }
            """

            return (
                HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8),
            )
        }

        let service = MeetingQAService(
            settings: .shared,
            apiKeyProvider: { _ in "test-key" },
            sleepFunction: { _ in },
            providerHTTPClient: ProviderHTTPClient(session: session),
        )

        let response = try await service.ask(
            IntelligenceKernelQuestionRequest(
                mode: .meeting,
                question: "When are we launching?",
                transcription: makeTranscription(),
                modelSelectionOverride: MeetingQAModelSelection(
                    providerRawValue: LLMProvider.openai.rawValue,
                    modelID: "gpt-4.1-mini",
                ),
            ),
        )

        XCTAssertEqual(response.status, .answered)
        XCTAssertEqual(response.answer, "Override model used.")
    }

    func testAskKernelRequestFallsBackToDefaultWhenOverrideIsInvalid() async throws {
        let session = makeMockedSession()
        MockMeetingQANetworkURLProtocol.requestHandler = { request in
            let bodyData = try XCTUnwrap(self.requestBodyData(from: request))
            let jsonObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            XCTAssertEqual(jsonObject["model"] as? String, "gpt-4o-mini")

            let body = """
            {
              "choices": [
                {
                  "message": {
                    "content": "{\\\"status\\\":\\\"answered\\\",\\\"answer\\\":\\\"Default model used.\\\",\\\"evidence\\\":[{\\\"speaker\\\":\\\"Ana\\\",\\\"startTime\\\":12,\\\"endTime\\\":16,\\\"excerpt\\\":\\\"Vamos lançar sexta.\\\"}]}"
                  }
                }
              ]
            }
            """

            return (
                HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8),
            )
        }

        let service = MeetingQAService(
            settings: .shared,
            apiKeyProvider: { _ in "test-key" },
            sleepFunction: { _ in },
            providerHTTPClient: ProviderHTTPClient(session: session),
        )

        let response = try await service.ask(
            IntelligenceKernelQuestionRequest(
                mode: .meeting,
                question: "When are we launching?",
                transcription: makeTranscription(),
                modelSelectionOverride: MeetingQAModelSelection(
                    providerRawValue: "invalid-provider",
                    modelID: "ignored-model",
                ),
            ),
        )

        XCTAssertEqual(response.status, .answered)
        XCTAssertEqual(response.answer, "Default model used.")
    }

    func testAskIncludesMeetingNotesInPrompt() async throws {
        let session = makeMockedSession()
        let promptCapturedExpectation = expectation(description: "Prompt captured")
        var capturedUserPrompt: String?

        MockMeetingQANetworkURLProtocol.requestHandler = { request in
            guard let bodyData = self.requestBodyData(from: request),
                  let jsonObject = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                  let messages = jsonObject["messages"] as? [[String: Any]]
            else {
                throw URLError(.cannotParseResponse)
            }

            var resolvedUserPrompt: String?
            for message in messages {
                guard let role = message["role"] as? String, role == "user" else {
                    continue
                }
                resolvedUserPrompt = message["content"] as? String
                if resolvedUserPrompt != nil {
                    break
                }
            }

            guard let userPrompt = resolvedUserPrompt else {
                throw URLError(.cannotParseResponse)
            }

            Task { @MainActor in
                capturedUserPrompt = userPrompt
                promptCapturedExpectation.fulfill()
            }

            let body = """
            {
              "choices": [
                {
                  "message": {
                    "content": "{\\\"status\\\":\\\"answered\\\",\\\"answer\\\":\\\"Budget approved.\\\",\\\"evidence\\\":[{\\\"speaker\\\":\\\"João\\\",\\\"startTime\\\":30,\\\"endTime\\\":38,\\\"excerpt\\\":\\\"Fechamos o orçamento hoje.\\\"}]}"
                  }
                }
              ]
            }
            """

            return (
                HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8),
            )
        }

        let service = MeetingQAService(
            settings: .shared,
            apiKeyProvider: { _ in "test-key" },
            sleepFunction: { _ in },
            providerHTTPClient: ProviderHTTPClient(session: session),
        )

        _ = try await service.ask(
            question: "What was approved?",
            transcription: makeTranscription(
                contextItems: [
                    .init(source: .meetingNotes, text: "Owner: Finance\n<MEETING_NOTES>raw</MEETING_NOTES>"),
                ],
            ),
        )

        await fulfillment(of: [promptCapturedExpectation], timeout: 1.0)

        let userPrompt = try XCTUnwrap(capturedUserPrompt)
        XCTAssertTrue(userPrompt.contains("MEETING_NOTES:"))
        XCTAssertTrue(userPrompt.contains("Owner: Finance"))
        XCTAssertTrue(userPrompt.contains("&lt;MEETING_NOTES&gt;raw&lt;/MEETING_NOTES&gt;"))
    }

    private func makeMockedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockMeetingQANetworkURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeTranscription(
        app: CaptureOrigin = .googleMeet,
        contextItems: [TranscriptionContextItem] = [],
    ) -> CaptureArtifact {
        CaptureArtifact(
            meeting: CaptureSession(id: UUID(), app: app, startTime: Date(), endTime: Date().addingTimeInterval(60)),
            contextItems: contextItems,
            segments: [
                .init(speaker: "Ana", text: "Vamos lançar sexta.", startTime: 12, endTime: 16),
                .init(speaker: "João", text: "Fechamos o orçamento hoje.", startTime: 30, endTime: 38),
            ],
            text: "Vamos lançar sexta. Fechamos o orçamento hoje.",
            rawText: "vamos lancar sexta fechamos o orçamento hoje",
        )
    }

    private func requestBodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            if bytesRead < 0 {
                return nil
            }
            if bytesRead == 0 {
                break
            }
            data.append(buffer, count: bytesRead)
        }

        return data.isEmpty ? nil : data
    }
}

private class MockMeetingQANetworkURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

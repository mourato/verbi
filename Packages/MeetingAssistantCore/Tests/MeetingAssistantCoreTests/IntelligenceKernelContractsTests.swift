import Foundation
@testable import MeetingAssistantCore
import XCTest

@MainActor
final class IntelligenceKernelContractsTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try AppSettingsTestIsolationLock.acquire()
    }

    override func tearDown() async throws {
        AppSettingsTestIsolationLock.release()
        try await super.tearDown()
    }

    func testAppSettingsReportsMeetingModeEnabledByDefault() {
        let settings = AppSettingsStore.shared

        XCTAssertEqual(settings.intelligenceKernelEnabled, FeatureFlags.enableIntelligenceKernel)
        XCTAssertTrue(settings.isIntelligenceKernelModeEnabled(.meeting))
        XCTAssertTrue(settings.isIntelligenceKernelModeEnabled(.dictation))
        XCTAssertFalse(settings.isIntelligenceKernelModeEnabled(.assistant))
    }

    func testMeetingQAServiceSupportsKernelRequestContract() async throws {
        let originalMeetingQnAEnabled = AppSettingsStore.shared.meetingQnAEnabled
        let originalAIConfiguration = AppSettingsStore.shared.aiConfiguration
        let originalEnhancementsAISelection = AppSettingsStore.shared.enhancementsAISelection
        defer {
            AppSettingsStore.shared.meetingQnAEnabled = originalMeetingQnAEnabled
            AppSettingsStore.shared.aiConfiguration = originalAIConfiguration
            AppSettingsStore.shared.enhancementsAISelection = originalEnhancementsAISelection
            MockKernelQANetworkURLProtocol.requestHandler = nil
        }

        AppSettingsStore.shared.meetingQnAEnabled = true
        AppSettingsStore.shared.aiConfiguration = AIConfiguration(
            provider: .openai,
            baseURL: "https://example.com/v1",
            selectedModel: "gpt-4o-mini",
        )
        AppSettingsStore.shared.enhancementsAISelection = EnhancementsAISelection(
            provider: .openai,
            selectedModel: "gpt-4o-mini",
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockKernelQANetworkURLProtocol.self]
        let session = URLSession(configuration: configuration)

        MockKernelQANetworkURLProtocol.requestHandler = { _ in
            let body = """
            {
              "choices": [
                {
                  "message": {
                    "content": "{\\\"status\\\":\\\"answered\\\",\\\"answer\\\":\\\"Decision logged.\\\",\\\"evidence\\\":[{\\\"speaker\\\":\\\"Ana\\\",\\\"startTime\\\":2,\\\"endTime\\\":4,\\\"excerpt\\\":\\\"Decision logged\\\"}]}"
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
                question: "What did we decide?",
                transcription: makeTranscription(),
                modelSelectionOverride: MeetingQAModelSelection(
                    providerRawValue: LLMProvider.openai.rawValue,
                    modelID: "gpt-4o-mini",
                ),
            ),
        )

        XCTAssertEqual(response.status, .answered)
        XCTAssertEqual(response.answer, "Decision logged.")
    }

    func testMeetingQAServiceDictationModeRemainsDisabled() async {
        let service = MeetingQAService(
            settings: .shared,
            apiKeyProvider: { _ in "test-key" },
            sleepFunction: { _ in },
        )

        do {
            _ = try await service.ask(
                IntelligenceKernelQuestionRequest(
                    mode: .dictation,
                    question: "What did I say?",
                    transcription: makeTranscription(),
                    modelSelectionOverride: nil,
                ),
            )
            XCTFail("Expected dictation Q&A to remain disabled")
        } catch let error as MeetingQAError {
            guard case .disabled = error else {
                return XCTFail("Expected .disabled, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeTranscription() -> CaptureArtifact {
        CaptureArtifact(
            meeting: CaptureSession(id: UUID(), app: .googleMeet, startTime: Date(), endTime: Date().addingTimeInterval(60)),
            segments: [
                .init(speaker: "Ana", text: "Decision logged", startTime: 2, endTime: 4),
            ],
            text: "Decision logged",
            rawText: "decision logged",
        )
    }
}

private class MockKernelQANetworkURLProtocol: URLProtocol {
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

@testable import VerbiCore
import XCTest

@MainActor
final class SpeechRecognitionClientAdapterTests: XCTestCase {
    func testExplicitRequestWithInvalidProviderFailsWithoutLegacyFallback() async {
        let client = MockTranscriptionClient()
        let adapter = SpeechRecognitionClientAdapter(transcriptionService: client)
        let configuration = DomainTranscriptionRequestConfiguration(
            providerID: "invalid-provider",
            modelID: "invalid-model",
            inputLanguageCode: nil,
        )

        do {
            _ = try await adapter.transcribe(
                audioURL: URL(fileURLWithPath: "/tmp/invalid-provider.m4a"),
                onProgress: nil,
                configuration: configuration,
                diarizationEnabledOverride: nil,
                capturePurpose: .meeting,
            )
            XCTFail("Expected invalid provider to fail")
        } catch {
            XCTAssertTrue(error is TranscriptionError)
            XCTAssertEqual(client.fileTranscribeCallCount, 0)
        }
    }
}

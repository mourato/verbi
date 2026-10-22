import Foundation
@testable import MeetingAssistantCore
import XCTest

@MainActor
extension RecordingManagerTests {
    func testRetryTranscription_PersistsRetryPerformanceAttempt() async throws {
        let manager = try XCTUnwrap(manager)
        let mockStorage = try XCTUnwrap(mockStorage)

        let rawURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        try writeRetryTestAudioFile(at: rawURL)
        defer { try? FileManager.default.removeItem(at: rawURL) }

        let transcription = CaptureArtifact(
            meeting: CaptureSession(app: .zoom, capturePurpose: .meeting, audioFilePath: rawURL.path),
            text: "Existing",
            rawText: "Existing",
            processedContent: nil,
            postProcessingPromptId: nil,
            postProcessingPromptTitle: nil,
            language: "en",
            modelName: "test-model",
        )

        await manager.retryTranscription(for: transcription)

        XCTAssertTrue(
            mockStorage.savedModelPerformanceAttempts.contains {
                $0.attemptKind == .retry && $0.stage == .transcription
            },
        )

        let saved = try XCTUnwrap(mockStorage.savedTranscriptions.last)
        XCTAssertEqual(saved.executionProvenance?.kernelMode, .meeting)
        XCTAssertNotNil(saved.executionProvenance?.usedStructuredPostProcessing)
    }

    func testRetryTranscription_PreservesPersistedAutomaticLanguage() async throws {
        let manager = try XCTUnwrap(manager)
        let mockTranscription = try XCTUnwrap(mockTranscription)

        readyRetryProviders = [.groq]
        let rawURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        try writeRetryTestAudioFile(at: rawURL)
        defer { try? FileManager.default.removeItem(at: rawURL) }

        let modelID = TranscriptionProvider.groqPresetModelIDs[0]
        let transcriptionRequest = DomainTranscriptionRequestConfiguration(
            providerID: TranscriptionProvider.groq.rawValue,
            modelID: modelID,
            inputLanguageCode: nil,
        )
        let transcription = CaptureArtifact(
            meeting: CaptureSession(app: .zoom, capturePurpose: .meeting, audioFilePath: rawURL.path),
            text: "Existing",
            rawText: "Existing",
            language: "en",
            modelName: modelID,
            executionProvenance: ExecutionProvenance(
                transcriptionRequest: transcriptionRequest,
                vocabularySnapshot: .empty,
                transcriptionModelIdentity: TranscriptionProvider.groq.modelPerformanceIdentity(modelID: modelID),
            ),
        )

        await manager.retryTranscription(for: transcription)

        XCTAssertNil(mockTranscription.lastTranscriptionConfiguration?.inputLanguageCode)
    }

    private func writeRetryTestAudioFile(at url: URL) throws {
        let data = Data(repeating: 0, count: 256)
        try data.write(to: url)
    }
}

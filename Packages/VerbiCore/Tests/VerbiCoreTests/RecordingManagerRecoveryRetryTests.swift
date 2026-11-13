import Foundation
@testable import VerbiCore
import VerbiCoreDomain
@testable import VerbiCoreUI
import XCTest

/// Recovery-retry coverage attached to `RecordingManagerTests`.
/// Run it with `--test RecordingManagerTests`; SwiftPM's file-name filter
/// cannot match extension-only test methods.
@MainActor
extension RecordingManagerTests {
    func testRecoveryRetry_IgnoresLivePostProcessingContext() async throws {
        let manager = try XCTUnwrap(manager)
        let mockTranscription = try XCTUnwrap(mockTranscription)
        let mockPostProcessing = try XCTUnwrap(mockPostProcessing)
        let settings = AppSettingsStore.shared
        settings.postProcessingEnabled = true
        settings.enhancementsAISelection = EnhancementsAISelection(provider: .openai, selectedModel: "gpt-4o")
        manager.postProcessingContext = "LIVE-CONTEXT"

        mockTranscription.mockText = "hello world"
        let recoveryArtifact = try makeRecoveryContextArtifact()
        await manager.retryTranscription(
            for: recoveryArtifact,
            vocabularyIntent: .originalSnapshot,
            recoveryMode: true
        )

        let processed = try XCTUnwrap(
            mockPostProcessing.lastProcessText,
            "Recovery retry must run post-processing in tests"
        )
        XCTAssertFalse(
            processed.contains("LIVE-CONTEXT"),
            "Recovery retries must not see the live post-processing context"
        )
    }

    func testRetry_IncludesLivePostProcessingContextByDefault() async throws {
        let manager = try XCTUnwrap(manager)
        let mockTranscription = try XCTUnwrap(mockTranscription)
        let mockPostProcessing = try XCTUnwrap(mockPostProcessing)
        let settings = AppSettingsStore.shared
        settings.postProcessingEnabled = true
        settings.enhancementsAISelection = EnhancementsAISelection(provider: .openai, selectedModel: "gpt-4o")
        manager.postProcessingContext = "LIVE-CONTEXT"

        mockTranscription.mockText = "hello world"
        let artifact = try makeRecoveryContextArtifact()
        await manager.retryTranscription(for: artifact, vocabularyIntent: .originalSnapshot)

        XCTAssertTrue(
            mockPostProcessing.lastProcessText?.contains("LIVE-CONTEXT") == true,
            "Default retries keep the live context; only recovery mode drops it"
        )
    }

    private func makeRecoveryContextArtifact() throws -> CaptureArtifact {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).wav")
        try Data(repeating: 0, count: 256).write(to: audioURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: audioURL)
        }
        return CaptureArtifact(
            meeting: CaptureSession(app: .zoom, capturePurpose: .meeting, audioFilePath: audioURL.path),
            text: "",
            rawText: "",
            language: "en",
            lifecycleState: .failed,
            transcriptionFailureReason: "test-stub"
        )
    }
}

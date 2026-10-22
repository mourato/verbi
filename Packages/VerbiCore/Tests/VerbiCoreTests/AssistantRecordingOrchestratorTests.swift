import Foundation
@testable import VerbiCore
@testable import VerbiCoreInfrastructure
@testable import VerbiCoreUI
import XCTest

@MainActor
final class AssistantRecordingOrchestratorTests: XCTestCase {
    override func tearDown() async throws {
        await RecordingExclusivityCoordinator.shared.endAssistant()
        await RecordingExclusivityCoordinator.shared.endRecording()
        try await super.tearDown()
    }

    func testCancelRecording_CleansUpEvenWhenRecorderAlreadyStopped() async {
        let manager = RecordingManager(
            transcriptionClient: MockTranscriptionClient(),
            postProcessingService: MockPostProcessingService(),
            storage: MockStorageService(),
        )
        manager.setPostProcessingReadinessWarning(issue: .missingAPIKey, mode: .assistant)

        let recorder = MockAssistantRecorderForOrchestrator()
        recorder.isRecording = false

        let indicator = FloatingRecordingIndicatorController(settingsStore: .shared)
        let screenBorder = AssistantScreenBorderController(settingsStore: .shared)
        var cancelSoundPlayed = false
        let orchestrator = AssistantRecordingOrchestrator(
            audioRecorder: recorder,
            recordingManager: manager,
            indicator: indicator,
            screenBorder: screenBorder,
            settings: .shared,
            playCancelSound: { cancelSoundPlayed = true },
        )

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("assistant-orchestrator-\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: tempURL.path, contents: Data("test".utf8))
        defer { try? FileManager.default.removeItem(at: tempURL) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))

        let acquiredBeforeCancel = await RecordingExclusivityCoordinator.shared.beginAssistant()
        XCTAssertTrue(acquiredBeforeCancel)

        await orchestrator.cancelRecording(currentRecordingURL: tempURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path))
        XCTAssertNil(manager.postProcessingReadinessWarningIssue)
        XCTAssertEqual(recorder.stopCallCount, 0)
        XCTAssertFalse(cancelSoundPlayed)
        let acquiredAfterCancel = await RecordingExclusivityCoordinator.shared.beginAssistant()
        XCTAssertTrue(acquiredAfterCancel)
    }
}

@MainActor
private final class MockAssistantRecorderForOrchestrator: AssistantRecordingService {
    var isRecording = false
    var stopCallCount = 0

    func startRecording(to _: URL, source _: RecordingSource, retryCount _: Int) async throws {
        isRecording = true
    }

    func stopRecording() async -> URL? {
        stopCallCount += 1
        isRecording = false
        return nil
    }

    func hasPermission() async -> Bool {
        true
    }

    func requestPermission() async {}
}

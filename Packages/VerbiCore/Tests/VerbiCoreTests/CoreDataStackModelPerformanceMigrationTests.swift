@testable import VerbiCore
import XCTest

final class ModelPerformanceMigrationTests: XCTestCase {
    func testBackfillClassifiesLegacyScribeV1AsElevenLabsRemote() async throws {
        let checkpointKey = "test.model_performance_backfill.scribe_v1.v1"
        UserDefaults.standard.removeObject(forKey: checkpointKey)
        defer { UserDefaults.standard.removeObject(forKey: checkpointKey) }

        let stack = CoreDataStack(name: "ModelPerformanceMigrationScribeV1", inMemory: true)
        let meetingRepo = CoreDataMeetingRepository(stack: stack)
        let transcriptionRepo = CoreDataTranscriptionStorageRepository(stack: stack)

        let meeting = CaptureSessionEntity(
            app: .unknown,
            capturePurpose: .dictation,
            startTime: Date(),
            endTime: Date().addingTimeInterval(60)
        )
        try await meetingRepo.saveMeeting(meeting)

        var config = CaptureArtifactEntity.Configuration(text: "Legacy dictation", rawText: "Legacy dictation")
        config.modelName = "scribe_v1"
        let transcription = CaptureArtifactEntity(meeting: meeting, config: config)
        try await transcriptionRepo.saveTranscription(transcription)

        await stack.backfillModelPerformanceAttemptsIfNeeded(checkpointKey: checkpointKey)

        let transcriptionID = transcription.id
        let attempts = try await stack.performBackgroundTask { context in
            try context.fetch(ModelPerformanceAttemptMO.fetchRequest(forTranscriptionID: transcriptionID))
                .map { $0.toDomain() }
        }

        let transcriptionAttempts = attempts.filter { $0.stage == .transcription }
        XCTAssertEqual(transcriptionAttempts.count, 1)
        let identity = try XCTUnwrap(transcriptionAttempts.first?.modelIdentity)
        XCTAssertEqual(identity.providerID, TranscriptionProvider.elevenLabs.rawValue)
        XCTAssertEqual(identity.modelID, "scribe_v1")
        XCTAssertEqual(identity.runtimeKind, .remote)
    }
}

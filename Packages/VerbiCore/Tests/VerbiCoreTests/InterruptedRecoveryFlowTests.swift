import Foundation
@testable import VerbiCoreDomain
@testable import VerbiCoreUI
import XCTest

final class InterruptedRecoveryFlowTests: XCTestCase {
    private var temporaryDirectories: [URL] = []
    private var storage: MockStorageService!
    private var directory: URL!
    private var harness: InterruptedRecoveryHarness!

    override func setUp() async throws {
        try await super.setUp()
        storage = MockStorageService()
        directory = try makeRecordingsDirectory()
        storage.recordingsDirectory = directory
        harness = InterruptedRecoveryHarness()
    }

    override func tearDown() {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories = []
        super.tearDown()
    }

    // MARK: - Fresh orphans

    func testFlow_RecoversFreshOrphan() async throws {
        let audioURL = try writeAudio(named: "crash.wav", in: directory)
        let flow = makeInterruptedRecoveryFlow(harness: harness, storage: storage)

        let recovered = await flow.run(recordingsDirectory: directory)

        XCTAssertEqual(recovered, 1)
        XCTAssertEqual(harness.summaryCounts, [1])
        XCTAssertEqual(harness.persistedRequests.count, 1)
        let saved = try await storage.loadTranscriptions()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(
            saved[0].meeting.audioFilePath.map { URL(fileURLWithPath: $0).standardizedFileURL.path },
            audioURL.standardizedFileURL.path
        )
        XCTAssertTrue(harness.stores.pending.isEmpty)
    }

    func testFlow_SingleNotificationForMultipleRecoveries() async throws {
        try writeAudio(named: "a.wav", in: directory)
        try writeAudio(named: "b.wav", in: directory)

        let recovered = await makeInterruptedRecoveryFlow(harness: harness, storage: storage).run(recordingsDirectory: directory)

        XCTAssertEqual(recovered, 2)
        XCTAssertEqual(harness.summaryCounts, [2])
    }

    func testFlow_IgnoresOldOrphans() async throws {
        let audioURL = try writeAudio(named: "old.wav", in: directory, date: Date().addingTimeInterval(-8 * 86400))

        let recovered = await makeInterruptedRecoveryFlow(harness: harness, storage: storage).run(recordingsDirectory: directory)

        XCTAssertEqual(recovered, 0)
        XCTAssertTrue(harness.summaryCounts.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))
    }

    func testFlow_PendingBypassesRecoveryWindow() async throws {
        let audioURL = try writeAudio(named: "pending.wav", in: directory, date: Date().addingTimeInterval(-30 * 86400))
        harness.stores.pending = ["pending.wav"]

        let recovered = await makeInterruptedRecoveryFlow(harness: harness, storage: storage).run(recordingsDirectory: directory)

        XCTAssertEqual(recovered, 1)
        let recoveredPath = try await storage.loadTranscriptions().first?.meeting.audioFilePath
        XCTAssertEqual(
            recoveredPath.map { URL(fileURLWithPath: $0).standardizedFileURL.path },
            audioURL.standardizedFileURL.path
        )
    }

    func testFlow_DoesNotResurrectDismissedAudio() async throws {
        try writeAudio(named: "deleted.wav", in: directory)
        harness.stores.dismissed = ["deleted.wav"]

        let recovered = await makeInterruptedRecoveryFlow(harness: harness, storage: storage).run(recordingsDirectory: directory)

        XCTAssertEqual(recovered, 0)
        let storedIsEmpty = try await storage.loadTranscriptions().isEmpty
        XCTAssertTrue(storedIsEmpty)
    }

    // MARK: - Active recordings (B1) and in-flight sessions (S1)

    func testFlow_SkipsActiveDuringScanThenRecoversAfterCrash() async throws {
        let audioURL = try writeAudio(named: "active.wav", in: directory)
        harness.activePaths = [audioURL.path]
        let flow = makeInterruptedRecoveryFlow(harness: harness, storage: storage)

        let first = await flow.run(recordingsDirectory: directory)

        XCTAssertEqual(first, 0)
        let storedIsEmpty = try await storage.loadTranscriptions().isEmpty
        XCTAssertTrue(storedIsEmpty)
        XCTAssertEqual(harness.stores.pending, ["active.wav"])

        // Simulate a crash: next launch has no active recording.
        harness.activePaths = []
        let second = await flow.run(recordingsDirectory: directory)

        XCTAssertEqual(second, 1)
        XCTAssertEqual(harness.summaryCounts, [1])
    }

    func testFlow_SkipsInFlightTranscriptionAudio() async throws {
        let sessionURL = try writeAudio(named: "session.wav", in: directory)
        harness.activePaths = [sessionURL.path]

        let recovered = await makeInterruptedRecoveryFlow(harness: harness, storage: storage).run(recordingsDirectory: directory)

        XCTAssertEqual(recovered, 0)
        let storedIsEmpty = try await storage.loadTranscriptions().isEmpty
        XCTAssertTrue(storedIsEmpty)
    }

    func testFlow_ReloadsReferencesBeforePersist() async throws {
        let audioURL = try writeAudio(named: "claimed.wav", in: directory)
        harness.metadataSnapshots = [
            [],
            [makeMetadata(audioFilePath: audioURL.path)]
        ]

        let recovered = await makeInterruptedRecoveryFlow(harness: harness, storage: storage).run(recordingsDirectory: directory)

        XCTAssertEqual(recovered, 0, "A file referenced after the scan must not gain a second entry")
        XCTAssertTrue(harness.persistedRequests.isEmpty)
        let storedIsEmpty = try await storage.loadTranscriptions().isEmpty
        XCTAssertTrue(storedIsEmpty)
    }

    // MARK: - Split recordings (S2) and purpose inference (N3)

    func testFlow_MergesSplitPartsIntoOneEntry() async throws {
        let micURL = try writeAudio(named: "meet_mic.wav", in: directory)
        let sysURL = try writeAudio(named: "meet_sys.wav", in: directory)

        let recovered = await makeInterruptedRecoveryFlow(harness: harness, storage: storage).run(recordingsDirectory: directory)

        XCTAssertEqual(recovered, 1)
        XCTAssertEqual(harness.mergeCalls.count, 1)
        XCTAssertEqual(Set(harness.mergeCalls[0].map(\.lastPathComponent)), ["meet_mic.wav", "meet_sys.wav"])
        let saved = try await storage.loadTranscriptions()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(
            saved[0].meeting.audioFilePath.map { URL(fileURLWithPath: $0).standardizedFileURL.path },
            directory.appendingPathComponent("meet.wav").standardizedFileURL.path
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: micURL.path),
            "Original parts are never destroyed by recovery"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: sysURL.path))

        let second = await makeInterruptedRecoveryFlow(harness: harness, storage: storage).run(recordingsDirectory: directory)

        XCTAssertEqual(second, 0, "Parts of a recovered merged file are owned, not re-offered")
        let storedAfterSecond = try await storage.loadTranscriptions()
        XCTAssertEqual(storedAfterSecond.count, 1)
    }

    func testFlow_UsesExistingMergedFileWithoutMerging() async throws {
        let mergedURL = try writeAudio(named: "meet.wav", in: directory)
        try writeAudio(named: "meet_mic.wav", in: directory)
        try writeAudio(named: "meet_sys.wav", in: directory)

        let recovered = await makeInterruptedRecoveryFlow(harness: harness, storage: storage).run(recordingsDirectory: directory)

        XCTAssertEqual(recovered, 1)
        XCTAssertTrue(harness.mergeCalls.isEmpty)
        let recoveredPath = try await storage.loadTranscriptions().first?.meeting.audioFilePath
        XCTAssertEqual(
            recoveredPath.map { URL(fileURLWithPath: $0).standardizedFileURL.path },
            mergedURL.standardizedFileURL.path
        )
    }

    func testFlow_UsesSinglePartWhenMergeFails() async throws {
        let micURL = try writeAudio(named: "meet_mic.wav", in: directory)
        try writeAudio(named: "meet_sys.wav", in: directory)
        harness.mergeSucceeds = false

        let recovered = await makeInterruptedRecoveryFlow(harness: harness, storage: storage).run(recordingsDirectory: directory)

        XCTAssertEqual(recovered, 1)
        let recoveredPath = try await storage.loadTranscriptions().first?.meeting.audioFilePath
        XCTAssertEqual(
            recoveredPath.map { URL(fileURLWithPath: $0).standardizedFileURL.path },
            micURL.standardizedFileURL.path
        )
    }

    func testFlow_InfersPurposeFromSplitParts() async throws {
        try writeAudio(named: "unknown_2026-01-01_mic.wav", in: directory)
        try writeAudio(named: "note_mic.wav", in: directory)
        try writeAudio(named: "call_sys.wav", in: directory)

        let recovered = await makeInterruptedRecoveryFlow(harness: harness, storage: storage).run(recordingsDirectory: directory)

        XCTAssertEqual(recovered, 3)
        let purposes = Dictionary(
            uniqueKeysWithValues: harness.persistedRequests.map { ($0.audioURL.lastPathComponent, $0.capturePurpose) }
        )
        XCTAssertEqual(purposes["unknown_2026-01-01_mic.wav"], .dictation)
        XCTAssertEqual(purposes["note_mic.wav"], .meeting, "Lone mic files default to meeting")
        XCTAssertEqual(purposes["call_sys.wav"], .meeting)
    }

    // MARK: - Readability, attempts, busy (S5, S9)

    func testFlow_SkipsUnreadableFileWithoutEntry() async throws {
        let audioURL = try writeAudio(named: "broken.wav", in: directory)
        harness.readableOverride = ["broken.wav": false]

        let recovered = await makeInterruptedRecoveryFlow(harness: harness, storage: storage).run(recordingsDirectory: directory)

        XCTAssertEqual(recovered, 0)
        XCTAssertTrue(harness.persistedRequests.isEmpty)
        let storedIsEmpty = try await storage.loadTranscriptions().isEmpty
        XCTAssertTrue(storedIsEmpty)
        XCTAssertTrue(harness.summaryCounts.isEmpty)
        XCTAssertEqual(harness.stores.attempts["broken.wav"], 1)
        XCTAssertTrue(harness.stores.pending.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path), "Unreadable files stay on disk")
    }

    func testFlow_CountsOnlySuccessesAndTracksAttempts() async throws {
        try writeAudio(named: "fail.wav", in: directory)
        harness.retrySucceeds = false
        let flow = makeInterruptedRecoveryFlow(harness: harness, storage: storage)

        let first = await flow.run(recordingsDirectory: directory)

        XCTAssertEqual(first, 0)
        XCTAssertTrue(harness.summaryCounts.isEmpty)
        XCTAssertEqual(harness.stores.attempts["fail.wav"], 1)
        XCTAssertEqual(harness.stores.pending, ["fail.wav"])

        harness.retrySucceeds = true
        try writeAudio(named: "fresh.wav", in: directory)
        let second = await flow.run(recordingsDirectory: directory)

        XCTAssertEqual(second, 1, "Only the newly transcribed file counts")
        XCTAssertEqual(harness.summaryCounts, [1])
        XCTAssertNil(harness.stores.attempts["fail.wav"])
    }

    func testFlow_SkipsWhenBusyWithoutCounting() async throws {
        try writeAudio(named: "busy.wav", in: directory)
        harness.busy = true

        let recovered = await makeInterruptedRecoveryFlow(harness: harness, storage: storage).run(recordingsDirectory: directory)

        XCTAssertEqual(recovered, 0)
        XCTAssertTrue(harness.persistedRequests.isEmpty)
        XCTAssertTrue(harness.summaryCounts.isEmpty)
        XCTAssertEqual(harness.stores.pending, ["busy.wav"])
    }

    func testFlow_StopsAutoRetryAfterAttemptCap() async throws {
        let audioURL = try writeAudio(named: "capped.wav", in: directory)
        try await saveFailedStub(title: InterruptedRecordingRecovery.recoveredTitle(), audioURL: audioURL)
        harness.stores.attempts = ["capped.wav": 3]

        let recovered = await makeInterruptedRecoveryFlow(harness: harness, storage: storage).run(recordingsDirectory: directory)

        XCTAssertEqual(recovered, 0)
        XCTAssertTrue(harness.retryCalls.isEmpty, "Capped files stay for manual retry")
        XCTAssertFalse(harness.stores.pending.contains("capped.wav"))
    }

    // MARK: - Previously failed recoveries

    func testFlow_RetriesFailedRecoveryStubWithoutCounting() async throws {
        let audioURL = try writeAudio(named: "failed.wav", in: directory)
        try await saveFailedStub(title: InterruptedRecordingRecovery.recoveredTitle(), audioURL: audioURL)

        let recovered = await makeInterruptedRecoveryFlow(harness: harness, storage: storage).run(recordingsDirectory: directory)

        XCTAssertEqual(recovered, 0, "Already-listed failures do not inflate the summary")
        XCTAssertEqual(harness.retryCalls, ["failed.wav"])
        XCTAssertTrue(harness.summaryCounts.isEmpty)
    }

    func testFlow_RetriesFailedDictationStubByArtifactTitle() async throws {
        let audioURL = try writeAudio(named: "failed.wav", in: directory)
        try await saveFailedStub(
            title: InterruptedRecordingRecovery.recoveredTitle(),
            audioURL: audioURL,
            purpose: .dictation
        )

        let recovered = await makeInterruptedRecoveryFlow(harness: harness, storage: storage).run(recordingsDirectory: directory)

        // Metadata titles are nil for dictations; matching uses the artifact.
        XCTAssertEqual(harness.retryCalls, ["failed.wav"])
        XCTAssertEqual(recovered, 0)
    }

    func testFlow_M4aMergedFileOwnsItsParts() async throws {
        let mergedURL = try writeAudio(named: "talk.m4a", in: directory)
        try writeAudio(named: "talk_mic.wav", in: directory)
        try writeAudio(named: "talk_sys.wav", in: directory)
        harness.stores.pending = ["talk_mic.wav", "talk_sys.wav", "talk.m4a"]

        let recovered = await makeInterruptedRecoveryFlow(harness: harness, storage: storage).run(recordingsDirectory: directory)

        XCTAssertEqual(recovered, 1, "Only the merged file is recovered")
        XCTAssertTrue(harness.mergeCalls.isEmpty, "No merge when a readable merged file exists")
        let saved = try await storage.loadTranscriptions()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(
            saved[0].meeting.audioFilePath.map { URL(fileURLWithPath: $0).standardizedFileURL.path },
            mergedURL.standardizedFileURL.path
        )

        let second = await makeInterruptedRecoveryFlow(harness: harness, storage: storage).run(recordingsDirectory: directory)

        XCTAssertEqual(second, 0, "Parts sharing the merged file's group key are never re-offered")
        let storedAfterSecond = try await storage.loadTranscriptions()
        XCTAssertEqual(storedAfterSecond.count, 1)
    }

    func testFlow_SysOrphanOwnedByReferencedMicIsSkipped() async throws {
        // Scenario B: a failed stop persisted an entry pointing at _mic;
        // the orphaned _sys part must not become a second partial entry.
        let micURL = try writeAudio(named: "meet_mic.wav", in: directory)
        try writeAudio(named: "meet_sys.wav", in: directory)
        try await saveFailedStub(title: "Manual entry", audioURL: micURL)

        let recovered = await makeInterruptedRecoveryFlow(harness: harness, storage: storage).run(recordingsDirectory: directory)

        XCTAssertEqual(recovered, 0)
        XCTAssertTrue(harness.persistedRequests.isEmpty)
        let storedCount = try await storage.loadTranscriptions().count
        XCTAssertEqual(storedCount, 1)
    }

    // MARK: - Harness

    private func saveFailedStub(title: String, audioURL: URL, purpose: CapturePurpose = .meeting) async throws {
        let meeting = CaptureSession(
            app: purpose == .dictation ? .unknown : .manualMeeting,
            capturePurpose: purpose,
            title: title,
            startTime: Date(),
            audioFilePath: audioURL.path
        )
        try await storage.saveTranscription(CaptureArtifact(
            meeting: meeting,
            text: "",
            rawText: "",
            lifecycleState: .failed,
            transcriptionFailureReason: "test-stub"
        ))
    }

    private func makeMetadata(audioFilePath: String) -> TranscriptionMetadata {
        TranscriptionMetadata(
            id: UUID(),
            meetingId: UUID(),
            meetingTitle: "Other",
            appName: "Manual",
            appRawValue: "manual-meeting",
            appBundleIdentifier: nil,
            startTime: Date(),
            createdAt: Date(),
            previewText: "",
            wordCount: 0,
            language: "en",
            isPostProcessed: false,
            duration: 0,
            audioFilePath: audioFilePath,
            inputSource: nil,
            lifecycleState: .completed
        )
    }

    private func makeRecordingsDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InterruptedRecoveryFlowTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }

    @discardableResult
    private func writeAudio(named filename: String, in directory: URL, byteCount: Int = 8, date: Date? = nil) throws -> URL {
        let url = directory.appendingPathComponent(filename)
        try Data(repeating: 0x01, count: byteCount).write(to: url)
        if let date {
            try FileManager.default.setAttributes(
                [.creationDate: date, .modificationDate: date],
                ofItemAtPath: url.path
            )
        }
        return url
    }
}

import Foundation
@testable import VerbiCoreDomain
import XCTest

final class InterruptedRecordingRecoveryTests: XCTestCase {
    private var temporaryDirectories: [URL] = []
    private var testDefaultsSuiteName: String?

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories = []
        if let suiteName = testDefaultsSuiteName {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
            testDefaultsSuiteName = nil
        }
        super.tearDown()
    }

    // MARK: - Orphan detection

    func testRecoverableOrphans_FindsUnreferencedAudio() throws {
        let directory = try makeRecordingsDirectory()
        let audioURL = try writeAudio(named: "crash_2026-01-01.wav", in: directory)

        let candidates = InterruptedRecordingRecovery.recoverableOrphans(
            in: directory,
            context: .init(
                knownAudioPaths: [],
                activeAudioPaths: [],
                dismissedFilenames: [],
                lastScanDate: nil,
                pendingFilenames: []
            )
        )

        XCTAssertEqual(
            candidates.map(\.url.standardizedFileURL.path),
            [audioURL.standardizedFileURL.path]
        )
    }

    func testRecoverableOrphans_SkipsReferencedAudio() throws {
        let directory = try makeRecordingsDirectory()
        let audioURL = try writeAudio(named: "saved.wav", in: directory)
        let nonStandardized = directory
            .appendingPathComponent("sub/../saved.wav").path

        let candidates = InterruptedRecordingRecovery.recoverableOrphans(
            in: directory,
            context: .init(
                knownAudioPaths: [nonStandardized],
                activeAudioPaths: [],
                dismissedFilenames: [],
                lastScanDate: nil,
                pendingFilenames: []
            )
        )

        XCTAssertTrue(candidates.isEmpty, "Referenced audio must not be recovered: \(audioURL.path)")
    }

    func testRecoverableOrphans_SkipsActiveRecording() throws {
        let directory = try makeRecordingsDirectory()
        let audioURL = try writeAudio(named: "in_progress.wav", in: directory)

        let candidates = InterruptedRecordingRecovery.recoverableOrphans(
            in: directory,
            context: .init(
                knownAudioPaths: [],
                activeAudioPaths: [audioURL.path],
                dismissedFilenames: [],
                lastScanDate: nil,
                pendingFilenames: []
            )
        )

        XCTAssertTrue(candidates.isEmpty)
    }

    func testRecoverableOrphans_SkipsEmptyAndUnsupportedFiles() throws {
        let directory = try makeRecordingsDirectory()
        try writeAudio(named: "empty.wav", in: directory, byteCount: 0)
        try writeAudio(named: "notes.txt", in: directory)

        let candidates = InterruptedRecordingRecovery.recoverableOrphans(
            in: directory,
            context: .init(
                knownAudioPaths: [],
                activeAudioPaths: [],
                dismissedFilenames: [],
                lastScanDate: nil,
                pendingFilenames: []
            )
        )

        XCTAssertTrue(candidates.isEmpty, "Empty and non-audio files stay on disk but are not recovered")
    }

    func testRecoverableOrphans_SkipsUserDeletedAudio() throws {
        let directory = try makeRecordingsDirectory()
        try writeAudio(named: "deleted.wav", in: directory)

        let candidates = InterruptedRecordingRecovery.recoverableOrphans(
            in: directory,
            context: .init(
                knownAudioPaths: [],
                activeAudioPaths: [],
                dismissedFilenames: ["deleted.wav"],
                lastScanDate: nil,
                pendingFilenames: []
            )
        )

        XCTAssertTrue(candidates.isEmpty, "User-deleted library entries must not be resurrected")
    }

    func testRecoverableOrphans_RespectsScanWatermark() throws {
        let directory = try makeRecordingsDirectory()
        let oldURL = try writeAudio(named: "old.wav", in: directory)
        try setCreationDate(oldURL, Date().addingTimeInterval(-2 * 86400))
        let recentURL = try writeAudio(named: "recent.wav", in: directory)
        let lastScan = Date().addingTimeInterval(-86400)

        let candidates = InterruptedRecordingRecovery.recoverableOrphans(
            in: directory,
            context: .init(
                knownAudioPaths: [],
                activeAudioPaths: [],
                dismissedFilenames: [],
                lastScanDate: lastScan,
                pendingFilenames: []
            )
        )

        XCTAssertEqual(
            candidates.map(\.url.standardizedFileURL.path),
            [recentURL.standardizedFileURL.path]
        )
    }

    func testRecoverableOrphans_RetriesPendingFilenamesRegardlessOfAge() throws {
        let directory = try makeRecordingsDirectory()
        let oldURL = try writeAudio(named: "pending.wav", in: directory)
        try setCreationDate(oldURL, Date().addingTimeInterval(-2 * 86400))

        let candidates = InterruptedRecordingRecovery.recoverableOrphans(
            in: directory,
            context: .init(
                knownAudioPaths: [],
                activeAudioPaths: [],
                dismissedFilenames: [],
                lastScanDate: Date(),
                pendingFilenames: ["pending.wav"]
            )
        )

        XCTAssertEqual(
            candidates.map(\.url.standardizedFileURL.path),
            [oldURL.standardizedFileURL.path]
        )
    }

    func testRecoverableOrphans_SortsOldestFirst() throws {
        let directory = try makeRecordingsDirectory()
        let newerURL = try writeAudio(named: "b_newer.wav", in: directory)
        try setCreationDate(newerURL, Date().addingTimeInterval(-100))
        let olderURL = try writeAudio(named: "a_older.wav", in: directory)
        try setCreationDate(olderURL, Date().addingTimeInterval(-200))

        let candidates = InterruptedRecordingRecovery.recoverableOrphans(
            in: directory,
            context: .init(
                knownAudioPaths: [],
                activeAudioPaths: [],
                dismissedFilenames: [],
                lastScanDate: nil,
                pendingFilenames: []
            )
        )

        XCTAssertEqual(
            candidates.map(\.url.standardizedFileURL.path),
            [olderURL.standardizedFileURL.path, newerURL.standardizedFileURL.path]
        )
    }

    // MARK: - Cleanup guard

    func testShouldDeleteOrphanedFile_DeletesOldSeenUnreferencedFiles() {
        let oldDate = Date().addingTimeInterval(-2 * 86400)

        XCTAssertTrue(
            InterruptedRecordingRecovery.shouldDeleteOrphanedFile(
                filename: "old.wav",
                createdAt: oldDate,
                isReferenced: false,
                pendingFilenames: [],
                lastScanDate: Date().addingTimeInterval(-86400)
            )
        )
    }

    func testShouldDeleteOrphanedFile_PreservesUnrecoveredFiles() {
        let oldDate = Date().addingTimeInterval(-2 * 86400)
        let lastScan = Date().addingTimeInterval(-86400)

        XCTAssertFalse(
            InterruptedRecordingRecovery.shouldDeleteOrphanedFile(
                filename: "referenced.wav",
                createdAt: oldDate,
                isReferenced: true,
                pendingFilenames: [],
                lastScanDate: lastScan
            ),
            "Referenced files are owned by retention rules, not the orphan sweep"
        )
        XCTAssertFalse(
            InterruptedRecordingRecovery.shouldDeleteOrphanedFile(
                filename: "pending.wav",
                createdAt: oldDate,
                isReferenced: false,
                pendingFilenames: ["pending.wav"],
                lastScanDate: lastScan
            ),
            "Files awaiting recovery retry must stay on disk"
        )
        XCTAssertFalse(
            InterruptedRecordingRecovery.shouldDeleteOrphanedFile(
                filename: "recent.wav",
                createdAt: Date(),
                isReferenced: false,
                pendingFilenames: [],
                lastScanDate: lastScan
            ),
            "Recent files may still be mid-recording"
        )
        XCTAssertFalse(
            InterruptedRecordingRecovery.shouldDeleteOrphanedFile(
                filename: "unseen.wav",
                createdAt: oldDate,
                isReferenced: false,
                pendingFilenames: [],
                lastScanDate: nil
            ),
            "Without a completed recovery scan, deletion is never safe"
        )
        XCTAssertFalse(
            InterruptedRecordingRecovery.shouldDeleteOrphanedFile(
                filename: "new-crash.wav",
                createdAt: Date(),
                isReferenced: false,
                pendingFilenames: [],
                lastScanDate: Date().addingTimeInterval(-86400)
            ),
            "Files created after the last scan never had a chance to be recovered"
        )
        XCTAssertFalse(
            InterruptedRecordingRecovery.shouldDeleteOrphanedFile(
                filename: "nodate.wav",
                createdAt: nil,
                isReferenced: false,
                pendingFilenames: [],
                lastScanDate: lastScan
            ),
            "Files without a usable date are preserved"
        )
    }

    // MARK: - Notification text

    func testNotificationBody_SelectsSingularAndPlural() {
        let singular = InterruptedRecordingRecovery.notificationBody(recoveredCount: 1)
        let plural = InterruptedRecordingRecovery.notificationBody(recoveredCount: 3)

        XCTAssertTrue(singular.contains("1"), "Singular body must carry the count: \(singular)")
        XCTAssertTrue(plural.contains("3"), "Plural body must carry the count: \(plural)")
        XCTAssertNotEqual(singular, plural)
    }

    func testRecoveredTitle_IsRecognizedAcrossLocales() {
        XCTAssertTrue(InterruptedRecordingRecovery.isRecoveredTitle("Recovered recording"))
        XCTAssertTrue(InterruptedRecordingRecovery.isRecoveredTitle("Gravação recuperada"))
        XCTAssertTrue(
            InterruptedRecordingRecovery.isRecoveredTitle(InterruptedRecordingRecovery.recoveredTitle())
        )
        XCTAssertFalse(InterruptedRecordingRecovery.isRecoveredTitle("Team standup"))
        XCTAssertFalse(InterruptedRecordingRecovery.isRecoveredTitle(nil))
    }

    // MARK: - Failed-recovery retry

    func testIsFailedRecoveryMetadata_MatchesOnlyFailedRecoveries() {
        let failedRecovery = makeMetadata(title: "Recovered recording", lifecycleState: .failed)
        let failedRecoveryPT = makeMetadata(title: "Gravação recuperada", lifecycleState: .failed)
        let completedRecovery = makeMetadata(title: "Recovered recording", lifecycleState: .completed)
        let failedRegular = makeMetadata(title: "Team standup", lifecycleState: .failed)

        XCTAssertTrue(InterruptedRecordingRecovery.isFailedRecoveryMetadata(failedRecovery))
        XCTAssertTrue(InterruptedRecordingRecovery.isFailedRecoveryMetadata(failedRecoveryPT))
        XCTAssertFalse(InterruptedRecordingRecovery.isFailedRecoveryMetadata(completedRecovery))
        XCTAssertFalse(InterruptedRecordingRecovery.isFailedRecoveryMetadata(failedRegular))
    }

    // MARK: - Stored state

    func testUserDeletedFilenames_AreRememberedByBasename() throws {
        let defaults = try makeTestDefaults()

        InterruptedRecordingRecovery.noteUserDeletedAudioFilenames(
            ["/recordings/deleted.wav", ""],
            defaults: defaults
        )

        XCTAssertEqual(
            InterruptedRecordingRecovery.loadDismissedFilenames(defaults: defaults),
            ["deleted.wav"]
        )
    }

    func testPendingFilenames_RoundTripThroughDefaults() throws {
        let defaults = try makeTestDefaults()

        InterruptedRecordingRecovery.savePendingFilenames(["a.wav", "b.wav"], defaults: defaults)

        XCTAssertEqual(
            InterruptedRecordingRecovery.loadPendingFilenames(defaults: defaults),
            ["a.wav", "b.wav"]
        )
    }

    // MARK: - Helpers

    private func makeRecordingsDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InterruptedRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }

    @discardableResult
    private func writeAudio(named filename: String, in directory: URL, byteCount: Int = 8) throws -> URL {
        let url = directory.appendingPathComponent(filename)
        try Data(repeating: 0x01, count: byteCount).write(to: url)
        return url
    }

    private func setCreationDate(_ url: URL, _ date: Date) throws {
        try FileManager.default.setAttributes([.creationDate: date], ofItemAtPath: url.path)
    }

    private func makeTestDefaults() throws -> UserDefaults {
        let suiteName = "InterruptedRecoveryTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        testDefaultsSuiteName = suiteName
        return defaults
    }

    private func makeMetadata(title: String?, lifecycleState: TranscriptionLifecycleState) -> TranscriptionMetadata {
        TranscriptionMetadata(
            id: UUID(),
            meetingId: UUID(),
            meetingTitle: title,
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
            audioFilePath: "/recordings/crash.wav",
            inputSource: nil,
            lifecycleState: lifecycleState
        )
    }
}

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
            context: .init()
        )

        XCTAssertEqual(
            candidates.map(\.url.standardizedFileURL.path),
            [audioURL.standardizedFileURL.path]
        )
    }

    func testRecoverableOrphans_SkipsReferencedAudio() throws {
        let directory = try makeRecordingsDirectory()
        try writeAudio(named: "saved.wav", in: directory)
        let nonStandardized = directory
            .appendingPathComponent("sub/../saved.wav").path

        let candidates = InterruptedRecordingRecovery.recoverableOrphans(
            in: directory,
            context: .init(knownAudioPaths: [nonStandardized])
        )

        XCTAssertTrue(candidates.isEmpty, "Referenced audio must not be recovered")
    }

    func testRecoverableOrphans_SkipsActiveRecording() throws {
        let directory = try makeRecordingsDirectory()
        let audioURL = try writeAudio(named: "in_progress.wav", in: directory)

        let candidates = InterruptedRecordingRecovery.recoverableOrphans(
            in: directory,
            context: .init(activeAudioPaths: [audioURL.path])
        )

        XCTAssertTrue(candidates.isEmpty)
    }

    func testRecoverableOrphans_SkipsEmptyAndUnsupportedFiles() throws {
        let directory = try makeRecordingsDirectory()
        try writeAudio(named: "empty.wav", in: directory, byteCount: 0)
        try writeAudio(named: "notes.txt", in: directory)

        let candidates = InterruptedRecordingRecovery.recoverableOrphans(
            in: directory,
            context: .init()
        )

        XCTAssertTrue(candidates.isEmpty, "Empty and non-audio files stay on disk but are not recovered")
    }

    func testRecoverableOrphans_SkipsUserDeletedAudio() throws {
        let directory = try makeRecordingsDirectory()
        try writeAudio(named: "deleted.wav", in: directory)

        let candidates = InterruptedRecordingRecovery.recoverableOrphans(
            in: directory,
            context: .init(dismissedFilenames: ["deleted.wav"])
        )

        XCTAssertTrue(candidates.isEmpty, "User-deleted library entries must not be resurrected")
    }

    func testRecoverableOrphans_OnlyOffersFilesInsideRecoveryWindow() throws {
        let directory = try makeRecordingsDirectory()
        let oldURL = try writeAudio(named: "old.wav", in: directory)
        try setDates(oldURL, Date().addingTimeInterval(-8 * 86400))
        let recentURL = try writeAudio(named: "recent.wav", in: directory)
        let now = Date()

        let candidates = InterruptedRecordingRecovery.recoverableOrphans(
            in: directory,
            context: .init(now: now)
        )

        XCTAssertEqual(
            candidates.map(\.url.standardizedFileURL.path),
            [recentURL.standardizedFileURL.path]
        )
    }

    func testRecoverableOrphans_RetriesPendingFilenamesRegardlessOfAge() throws {
        let directory = try makeRecordingsDirectory()
        let oldURL = try writeAudio(named: "pending.wav", in: directory)
        try setDates(oldURL, Date().addingTimeInterval(-30 * 86400))

        let candidates = InterruptedRecordingRecovery.recoverableOrphans(
            in: directory,
            context: .init(pendingFilenames: ["pending.wav"], now: Date())
        )

        XCTAssertEqual(
            candidates.map(\.url.standardizedFileURL.path),
            [oldURL.standardizedFileURL.path]
        )
    }

    func testRecoverableOrphans_SortsOldestFirst() throws {
        let directory = try makeRecordingsDirectory()
        let newerURL = try writeAudio(named: "b_newer.wav", in: directory)
        try setDates(newerURL, Date().addingTimeInterval(-100))
        let olderURL = try writeAudio(named: "a_older.wav", in: directory)
        try setDates(olderURL, Date().addingTimeInterval(-200))

        let candidates = InterruptedRecordingRecovery.recoverableOrphans(
            in: directory,
            context: .init()
        )

        XCTAssertEqual(
            candidates.map(\.url.standardizedFileURL.path),
            [olderURL.standardizedFileURL.path, newerURL.standardizedFileURL.path]
        )
    }

    // MARK: - Split grouping (S2) and purpose inference (N3)

    func testGroupSplitParts_GroupsMicrophoneAndSystemParts() throws {
        let directory = try makeRecordingsDirectory()
        let micURL = try writeAudio(named: "meet_2026-01-01_mic.wav", in: directory)
        let sysURL = try writeAudio(named: "meet_2026-01-01_sys.wav", in: directory)
        let now = Date()

        let groups = InterruptedRecordingRecovery.groupSplitParts([
            .init(url: micURL, createdAt: now),
            .init(url: sysURL, createdAt: now)
        ])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].baseName, "meet_2026-01-01")
        XCTAssertEqual(groups[0].microphoneURL, micURL)
        XCTAssertEqual(groups[0].systemURL, sysURL)
        XCTAssertNil(groups[0].mergedURL)
        XCTAssertEqual(groups[0].inferredCapturePurpose, .meeting)
    }

    func testGroupSplitParts_InfersDictationOnlyForUnknownAppMicrophonePart() throws {
        let directory = try makeRecordingsDirectory()
        let dictationURL = try writeAudio(named: "unknown_2026-01-01_mic.wav", in: directory)
        let meetingMicURL = try writeAudio(named: "note_mic.wav", in: directory)

        let groups = InterruptedRecordingRecovery.groupSplitParts([
            .init(url: dictationURL, createdAt: Date()),
            .init(url: meetingMicURL, createdAt: Date())
        ])
        let purposes = Dictionary(uniqueKeysWithValues: groups.map { ($0.baseName, $0.inferredCapturePurpose) })

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(purposes["note"], .meeting, "Lone mic files default to meeting")
        XCTAssertEqual(purposes["unknown_2026-01-01"], .dictation)
    }

    func testGroupSplitParts_InfersMeetingForMergedFile() throws {
        let directory = try makeRecordingsDirectory()
        let mergedURL = try writeAudio(named: "meet_2026-01-01.wav", in: directory)

        let groups = InterruptedRecordingRecovery.groupSplitParts([.init(url: mergedURL, createdAt: Date())])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].mergedURL, mergedURL)
        XCTAssertEqual(groups[0].inferredCapturePurpose, .meeting)
    }

    func testNormalizedGroupKey_IgnoresExtensionPartAndCase() {
        XCTAssertEqual(
            InterruptedRecordingRecovery.normalizedGroupKey(filename: "Meet_2026-01-01_MIC.WAV"),
            "meet_2026-01-01"
        )
        XCTAssertEqual(
            InterruptedRecordingRecovery.normalizedGroupKey(filename: "meet_2026-01-01_sys.wav"),
            "meet_2026-01-01"
        )
        XCTAssertEqual(
            InterruptedRecordingRecovery.normalizedGroupKey(filename: "meet_2026-01-01.m4a"),
            "meet_2026-01-01"
        )
    }

    func testReferencedGroupKeys_OnlyIncludesRecordingsDirectoryAudio() throws {
        let directory = try makeRecordingsDirectory()
        let insideURL = try writeAudio(named: "talk_mic.wav", in: directory)

        let keys = InterruptedRecordingRecovery.referencedGroupKeys(
            audioPaths: [insideURL.path, "/elsewhere/other_mic.wav"],
            recordingsDirectory: directory
        )

        XCTAssertEqual(keys, ["talk"])
    }

    func testMergedFileExtension_FollowsParts() throws {
        let directory = try makeRecordingsDirectory()
        let micURL = try writeAudio(named: "talk_mic.m4a", in: directory)
        let sysURL = try writeAudio(named: "talk_sys.m4a", in: directory)

        let groups = InterruptedRecordingRecovery.groupSplitParts([
            .init(url: micURL, createdAt: Date()),
            .init(url: sysURL, createdAt: Date())
        ])

        XCTAssertEqual(InterruptedRecordingRecovery.mergedFileExtension(for: groups[0]), "m4a")
        XCTAssertEqual(
            InterruptedRecordingRecovery.mergedOutputURL(for: groups[0], in: directory)?.pathExtension,
            "m4a"
        )
    }

    func testMergedOutputURL_ReturnsNilWhenNameIsTaken() throws {
        let directory = try makeRecordingsDirectory()
        let mergedURL = try writeAudio(named: "meet.wav", in: directory)

        let groups = InterruptedRecordingRecovery.groupSplitParts([.init(url: mergedURL, createdAt: Date())])

        XCTAssertNil(
            InterruptedRecordingRecovery.mergedOutputURL(for: groups[0], in: directory),
            "An existing merged file must never be replaced silently"
        )
    }

    // MARK: - Cleanup guard (S4)

    func testShouldDeleteOrphanedFile_DeletesOldSeenUnreferencedFiles() {
        let oldDate = Date().addingTimeInterval(-30 * 86400)

        XCTAssertTrue(
            InterruptedRecordingRecovery.shouldDeleteOrphanedFile(
                filename: "old.wav",
                createdAt: oldDate,
                isReferenced: false,
                pendingFilenames: [],
                dismissedFilenames: []
            )
        )
    }

    func testShouldDeleteOrphanedFile_DeletesDismissedFilesPastTheAgeThreshold() {
        let oldDate = Date().addingTimeInterval(-2 * 86400)

        XCTAssertTrue(
            InterruptedRecordingRecovery.shouldDeleteOrphanedFile(
                filename: "deleted.wav",
                createdAt: oldDate,
                isReferenced: false,
                pendingFilenames: [],
                dismissedFilenames: ["deleted.wav"]
            )
        )
    }

    func testShouldDeleteOrphanedFile_PreservesUnrecoveredFiles() {
        let oldDate = Date().addingTimeInterval(-30 * 86400)
        let recentDate = Date().addingTimeInterval(-3600)

        XCTAssertFalse(
            InterruptedRecordingRecovery.shouldDeleteOrphanedFile(
                filename: "referenced.wav",
                createdAt: oldDate,
                isReferenced: true,
                pendingFilenames: [],
                dismissedFilenames: []
            ),
            "Referenced files are owned by retention rules, not the orphan sweep"
        )
        XCTAssertFalse(
            InterruptedRecordingRecovery.shouldDeleteOrphanedFile(
                filename: "pending.wav",
                createdAt: oldDate,
                isReferenced: false,
                pendingFilenames: ["pending.wav"],
                dismissedFilenames: []
            ),
            "Files awaiting recovery retry must stay on disk"
        )
        XCTAssertFalse(
            InterruptedRecordingRecovery.shouldDeleteOrphanedFile(
                filename: "recent.wav",
                createdAt: recentDate,
                isReferenced: false,
                pendingFilenames: [],
                dismissedFilenames: []
            ),
            "Recent files may still be mid-recording"
        )
        XCTAssertFalse(
            InterruptedRecordingRecovery.shouldDeleteOrphanedFile(
                filename: "window.wav",
                createdAt: Date().addingTimeInterval(-2 * 86400),
                isReferenced: false,
                pendingFilenames: [],
                dismissedFilenames: []
            ),
            "Unreferenced orphans inside the recovery window are never deleted"
        )
        XCTAssertFalse(
            InterruptedRecordingRecovery.shouldDeleteOrphanedFile(
                filename: "nodate.wav",
                createdAt: nil,
                isReferenced: false,
                pendingFilenames: [],
                dismissedFilenames: []
            ),
            "Files without a usable date are preserved"
        )
    }

    // MARK: - Retry accounting (S5) and store pruning (N1)

    func testAutoRetry_StopsAfterMaxAttempts() {
        XCTAssertTrue(InterruptedRecordingRecovery.autoRetryAllowed(filename: "a.wav", attempts: [:]))
        let twice = InterruptedRecordingRecovery.recordingFailedAttempt(filename: "a.wav", attempts: ["a.wav": 1])
        XCTAssertTrue(InterruptedRecordingRecovery.autoRetryAllowed(filename: "a.wav", attempts: twice))
        let capped = InterruptedRecordingRecovery.recordingFailedAttempt(filename: "a.wav", attempts: twice)
        XCTAssertFalse(InterruptedRecordingRecovery.autoRetryAllowed(filename: "a.wav", attempts: capped))
    }

    func testPrunedStores_DropsMissingAndRereferencedFiles() {
        let stores = InterruptedRecordingRecovery.Stores(
            pending: ["gone.wav", "back.wav", "keep.wav"],
            dismissed: ["gone.wav", "deleted.wav"],
            attempts: ["gone.wav": 2, "keep.wav": 1, "capped.wav": 3]
        )

        let pruned = InterruptedRecordingRecovery.prunedStores(
            stores,
            existingFilenames: ["back.wav", "keep.wav", "deleted.wav", "capped.wav"],
            referencedFilenames: ["back.wav"]
        )

        XCTAssertEqual(pruned.pending, ["keep.wav"])
        XCTAssertEqual(pruned.dismissed, ["deleted.wav"])
        XCTAssertEqual(pruned.attempts, ["keep.wav": 1, "capped.wav": 3])
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

    // MARK: - Stored state

    func testUserDeletedFilenames_AreRememberedByBasename() throws {
        let defaults = try makeTestDefaults()

        InterruptedRecordingRecovery.noteUserDeletedAudioFilenames(
            ["/recordings/deleted.wav", ""],
            defaults: defaults
        )

        XCTAssertEqual(
            InterruptedRecordingRecovery.loadStores(defaults: defaults).dismissed,
            ["deleted.wav"]
        )
    }

    func testStores_RoundTripThroughDefaults() throws {
        let defaults = try makeTestDefaults()

        InterruptedRecordingRecovery.saveStores(
            .init(pending: ["a.wav"], dismissed: ["b.wav"], attempts: ["a.wav": 2]),
            defaults: defaults
        )

        XCTAssertEqual(
            InterruptedRecordingRecovery.loadStores(defaults: defaults),
            .init(pending: ["a.wav"], dismissed: ["b.wav"], attempts: ["a.wav": 2])
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

    private func setDates(_ url: URL, _ date: Date) throws {
        try FileManager.default.setAttributes(
            [.creationDate: date, .modificationDate: date],
            ofItemAtPath: url.path
        )
    }

    private func makeTestDefaults() throws -> UserDefaults {
        let suiteName = "InterruptedRecoveryTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        testDefaultsSuiteName = suiteName
        return defaults
    }
}

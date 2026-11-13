import Foundation
@testable import VerbiCoreData
@testable import VerbiCoreDomain
import XCTest

/// End-to-end interaction between the recovery guards and both deletion
/// paths: the orphan sweep decision and the retention preview. Uses temp
/// directories and fakes, no sleeps.
final class RetentionCleanupRecoveryTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories = []
        super.tearDown()
    }

    // MARK: - Retention preview (S4)

    func testRetentionPreview_NeverDeletesUnrecoveredOrphans() throws {
        let directory = try makeRecordingsDirectory()
        let now = Date()
        let oldDate = now.addingTimeInterval(-30 * 86400)
        let recentDate = now.addingTimeInterval(-1 * 86400)

        let oldReferenced = try writeAudio(named: "old_ref.wav", in: directory, date: oldDate)
        let recentReferenced = try writeAudio(named: "recent_ref.wav", in: directory, date: recentDate)
        try writeAudio(named: "orphan_old.wav", in: directory, date: oldDate)
        try writeAudio(named: "orphan_recent.wav", in: directory, date: recentDate)
        try writeAudio(named: "orphan_pending.wav", in: directory, date: oldDate)
        try writeAudio(named: "dismissed_recent.wav", in: directory, date: now.addingTimeInterval(-12 * 3600))
        try writeAudio(named: "empty_old.wav", in: directory, date: oldDate, byteCount: 0)

        let preview = FileSystemStorageService.computeRetentionCleanupPreviewSync(
            context: .init(
                retentionDays: 7,
                cutoffDate: now.addingTimeInterval(-7 * 86400),
                recordingsDir: directory.standardizedFileURL,
                audioPathsToKeep: [recentReferenced.standardizedFileURL.path],
                audioPathsEligibleForDeletion: [oldReferenced.standardizedFileURL.path],
                pendingFilenames: ["orphan_pending.wav"],
                dismissedFilenames: ["dismissed_recent.wav"],
                now: now
            )
        )

        let deleted = Set(preview.audioFiles.map(\.url.lastPathComponent))
        XCTAssertTrue(deleted.contains("old_ref.wav"), "Old referenced audio follows retention rules")
        XCTAssertTrue(deleted.contains("orphan_old.wav"), "Old unclaimed orphans follow retention rules")
        XCTAssertTrue(deleted.contains("empty_old.wav"), "Old empty files follow retention rules")
        XCTAssertFalse(deleted.contains("recent_ref.wav"), "Recent referenced audio is kept")
        XCTAssertFalse(deleted.contains("orphan_recent.wav"), "Orphans inside the recovery window are never deleted")
        XCTAssertFalse(deleted.contains("orphan_pending.wav"), "Pending retries are never deleted")
        XCTAssertFalse(
            deleted.contains("dismissed_recent.wav"),
            "User-dismissed files still follow the age rule before deletion"
        )
    }

    // MARK: - Orphan sweep decision

    func testOrphanSweep_DeletesOnlyOldClaimedOrDismissedOrphans() throws {
        let directory = try makeRecordingsDirectory()
        let now = Date()
        let oldDate = now.addingTimeInterval(-30 * 86400)

        try writeAudio(named: "known.wav", in: directory, date: oldDate)
        try writeAudio(named: "orphan_old.wav", in: directory, date: oldDate)
        try writeAudio(named: "orphan_recent.wav", in: directory, date: now.addingTimeInterval(-3600))
        try writeAudio(named: "orphan_pending.wav", in: directory, date: oldDate)
        try writeAudio(named: "dismissed_old.wav", in: directory, date: oldDate)

        let deletable = FileSystemStorageService.orphanedFilesToDelete(
            in: directory,
            knownAudioPaths: [directory.appendingPathComponent("known.wav").path],
            stores: .init(pending: ["orphan_pending.wav"], dismissed: ["dismissed_old.wav"]),
            now: now
        )

        XCTAssertEqual(
            Set(deletable.map(\.lastPathComponent)),
            ["orphan_old.wav", "dismissed_old.wav"]
        )
    }

    // MARK: - Helpers

    private func makeRecordingsDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RetentionCleanupRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }

    @discardableResult
    private func writeAudio(named filename: String, in directory: URL, date: Date, byteCount: Int = 8) throws -> URL {
        let url = directory.appendingPathComponent(filename)
        try Data(repeating: 0x01, count: byteCount).write(to: url)
        try FileManager.default.setAttributes(
            [.creationDate: date, .modificationDate: date],
            ofItemAtPath: url.path
        )
        return url
    }
}

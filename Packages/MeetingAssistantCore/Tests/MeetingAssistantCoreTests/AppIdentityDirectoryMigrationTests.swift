import Foundation
@testable import MeetingAssistantCore
import XCTest

final class AppIdentityDirectoryMigrationTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("verbi-identity-migration-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        temporaryRoot = nil
    }

    func testMovesNewestLegacyDirectoryOntoCurrent() throws {
        let current = temporaryRoot.appendingPathComponent("Verbi", isDirectory: true)
        let prisma = temporaryRoot.appendingPathComponent("Prisma", isDirectory: true)
        let meetingAssistant = temporaryRoot.appendingPathComponent("MeetingAssistant", isDirectory: true)
        try FileManager.default.createDirectory(at: prisma, withIntermediateDirectories: true)
        try "prisma".write(to: prisma.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: meetingAssistant, withIntermediateDirectories: true)

        let resolved = AppIdentity.resolveMigratedDirectory(
            currentURL: current,
            legacyURLs: [prisma, meetingAssistant],
            fileManager: .default,
        )

        XCTAssertEqual(resolved.path, current.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: current.appendingPathComponent("marker.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: prisma.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: meetingAssistant.path))
    }

    func testFallsBackToOlderLegacyWhenNewerAbsent() throws {
        let current = temporaryRoot.appendingPathComponent("Verbi", isDirectory: true)
        let prisma = temporaryRoot.appendingPathComponent("Prisma", isDirectory: true)
        let meetingAssistant = temporaryRoot.appendingPathComponent("MeetingAssistant", isDirectory: true)
        try FileManager.default.createDirectory(at: meetingAssistant, withIntermediateDirectories: true)
        try "legacy".write(to: meetingAssistant.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)

        let resolved = AppIdentity.resolveMigratedDirectory(
            currentURL: current,
            legacyURLs: [prisma, meetingAssistant],
            fileManager: .default,
        )

        XCTAssertEqual(resolved.path, current.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: current.appendingPathComponent("marker.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: meetingAssistant.path))
    }

    func testKeepsCurrentWhenAlreadyPresent() throws {
        let current = temporaryRoot.appendingPathComponent("Verbi", isDirectory: true)
        let prisma = temporaryRoot.appendingPathComponent("Prisma", isDirectory: true)
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: prisma, withIntermediateDirectories: true)
        try "current".write(to: current.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)
        try "legacy".write(to: prisma.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)

        let resolved = AppIdentity.resolveMigratedDirectory(
            currentURL: current,
            legacyURLs: [prisma],
            fileManager: .default,
        )

        XCTAssertEqual(resolved.path, current.path)
        let contents = try String(contentsOf: current.appendingPathComponent("marker.txt"), encoding: .utf8)
        XCTAssertEqual(contents, "current")
        XCTAssertTrue(FileManager.default.fileExists(atPath: prisma.path))
    }
}

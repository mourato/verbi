import CoreData
@testable import VerbiCore
import XCTest

final class StorageServiceSecurityTests: XCTestCase {
    private var appSupportRoot: String {
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory).path
    }

    private var homeDirectory: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "recordingsDirectory")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "recordingsDirectory")
        super.tearDown()
    }

    func testPathTraversalBlocked() {
        // Given: Path with traversal pattern
        let maliciousPath = "/Users/attacker/../../../etc/passwd"
        UserDefaults.standard.set(maliciousPath, forKey: "recordingsDirectory")

        // When: Accessing recordings directory
        let service = FileSystemStorageService()
        let directory = service.recordingsDirectory

        // Then: Should fallback to default, not malicious path
        XCTAssertFalse(directory.path.contains("etc/passwd"))
        XCTAssertTrue(directory.path.hasPrefix(appSupportRoot))
    }

    func testSymlinkResolution() {
        // Given: Path that could be a symlink
        let service = FileSystemStorageService()

        // When: Getting recordings directory
        let directory = service.recordingsDirectory

        // Then: Should be resolved (no symlinks in path should lead outside container)
        XCTAssertTrue(directory.path.hasPrefix(appSupportRoot))
    }

    func testOutsideContainerBlocked() {
        // Given: Valid-looking path outside user-accessible locations
        let outsidePath = "/tmp/recordings"
        UserDefaults.standard.set(outsidePath, forKey: "recordingsDirectory")

        // When: Accessing recordings directory
        let service = FileSystemStorageService()
        let directory = service.recordingsDirectory

        // Then: Should fallback to default (paths outside home/Volumes are blocked)
        XCTAssertFalse(directory.path.hasPrefix("/tmp"))
        XCTAssertTrue(directory.path.hasPrefix(appSupportRoot))
    }

    func testUserAccessiblePathAllowed() {
        // Given: Valid path under the user's home directory
        let validPath = homeDirectory + "/Documents/PrismaRecordings"
        UserDefaults.standard.set(validPath, forKey: "recordingsDirectory")

        // When: Accessing recordings directory
        let service = FileSystemStorageService(honorsConfiguredRecordingDirectory: true)
        let directory = service.recordingsDirectory

        // Then: Should use the configured path, not the default
        XCTAssertTrue(directory.path.hasPrefix(homeDirectory + "/Documents/PrismaRecordings"))
    }

    func testDefaultInitIgnoresConfiguredUserPathWhileRunningTests() {
        // Given: A real user path persisted in defaults
        let validPath = homeDirectory + "/Documents/PrismaRecordings"
        UserDefaults.standard.set(validPath, forKey: "recordingsDirectory")

        // When: Accessing recordings directory through the default test configuration
        let service = FileSystemStorageService()
        let directory = service.recordingsDirectory

        // Then: Tests should stay inside app-managed storage instead of touching user folders
        XCTAssertTrue(AppIdentity.isRunningTests)
        XCTAssertTrue(directory.path.hasPrefix(appSupportRoot))
        XCTAssertFalse(directory.path.hasPrefix(validPath))
    }

    func testCoreDataStackDefaultsToInMemoryWhileRunningTests() {
        let stack = CoreDataStack(name: "StorageServiceSecurityTests.\(UUID().uuidString)")
        let storeType = stack.mainContext.persistentStoreCoordinator?.persistentStores.first?.type

        XCTAssertTrue(AppIdentity.isRunningTests)
        XCTAssertEqual(storeType, NSInMemoryStoreType)
    }

    func testEmptyPathFallsBackToDefault() {
        // Given: Empty path
        UserDefaults.standard.set("", forKey: "recordingsDirectory")

        // When: Accessing recordings directory
        let service = FileSystemStorageService()
        let directory = service.recordingsDirectory

        // Then: Should use the default recordings directory
        XCTAssertTrue(directory.path.hasPrefix(appSupportRoot))
    }
}

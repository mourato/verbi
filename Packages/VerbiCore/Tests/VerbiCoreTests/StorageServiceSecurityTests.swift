import CoreData
@testable import VerbiCore
@testable import VerbiCoreData
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
        let maliciousPath = "/Users/attacker/../../../etc/passwd"
        UserDefaults.standard.set(maliciousPath, forKey: "recordingsDirectory")

        let service = FileSystemStorageService()
        let directory = service.recordingsDirectory

        XCTAssertFalse(directory.path.contains("etc/passwd"))
        XCTAssertTrue(directory.path.hasPrefix(appSupportRoot))
    }

    func testSymlinkResolution() {
        let service = FileSystemStorageService()

        let directory = service.recordingsDirectory

        XCTAssertTrue(directory.path.hasPrefix(appSupportRoot))
    }

    func testOutsideContainerBlocked() {
        let outsidePath = "/tmp/recordings"
        UserDefaults.standard.set(outsidePath, forKey: "recordingsDirectory")

        let service = FileSystemStorageService()
        let directory = service.recordingsDirectory

        XCTAssertFalse(directory.path.hasPrefix("/tmp"))
        XCTAssertTrue(directory.path.hasPrefix(appSupportRoot))
    }

    func testUserAccessiblePathAllowed() {
        let validPath = homeDirectory + "/Documents/PrismaRecordings"
        UserDefaults.standard.set(validPath, forKey: "recordingsDirectory")

        let service = FileSystemStorageService(honorsConfiguredRecordingDirectory: true)
        let directory = service.recordingsDirectory

        XCTAssertTrue(directory.path.hasPrefix(homeDirectory + "/Documents/PrismaRecordings"))
    }

    func testDefaultInitIgnoresConfiguredUserPathWhileRunningTests() {
        let validPath = homeDirectory + "/Documents/PrismaRecordings"
        UserDefaults.standard.set(validPath, forKey: "recordingsDirectory")

        let service = FileSystemStorageService()
        let directory = service.recordingsDirectory

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

    func testRecordingPathRejectsSiblingDirectorySharingHomePrefix() {
        let siblingPath = homeDirectory + "-sibling/recordings.m4a"
        XCTAssertTrue(siblingPath.hasPrefix(homeDirectory))

        let service = FileSystemStorageService()

        XCTAssertThrowsError(try service.validateRecordingPath(siblingPath)) { error in
            guard case FileSystemStorageService.PathValidationError.outsideContainer = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testPathBoundaryRequiresDirectoryMatch() {
        let containerRoot = AppIdentity.appSupportBaseDirectory(fileManager: .default).path

        XCTAssertTrue(FileSystemStorageService.isInside(containerRoot, root: containerRoot))
        XCTAssertTrue(FileSystemStorageService.isInside(containerRoot + "/recordings", root: containerRoot))
        XCTAssertFalse(FileSystemStorageService.isInside(containerRoot + "-sibling/recordings", root: containerRoot))
        XCTAssertTrue(FileSystemStorageService.isInside("/Volumes/External/recording.m4a", root: "/Volumes"))
        XCTAssertFalse(FileSystemStorageService.isInside("/VolumesExternal/recording.m4a", root: "/Volumes"))
        XCTAssertFalse(FileSystemStorageService.isInside("/tmp/recordings", root: containerRoot))
    }

    func testEmptyPathFallsBackToDefault() {
        UserDefaults.standard.set("", forKey: "recordingsDirectory")

        let service = FileSystemStorageService()
        let directory = service.recordingsDirectory

        XCTAssertTrue(directory.path.hasPrefix(appSupportRoot))
    }
}

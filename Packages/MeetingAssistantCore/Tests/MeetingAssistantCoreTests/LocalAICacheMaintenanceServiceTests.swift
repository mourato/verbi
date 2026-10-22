import Foundation
@testable import MeetingAssistantCoreAI
import MeetingAssistantCoreDomain
@testable import MeetingAssistantCoreInfrastructure
import XCTest

@MainActor
final class LocalAICacheMaintenanceServiceTests: XCTestCase {
    func testComputeCleanupPreview_WhenRuntimeActive_ExcludesAppleRuntimeCache() async throws {
        let rootDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let appleCacheRoot = rootDirectory.appendingPathComponent("AppleCache", isDirectory: true)
        let bucketDirectory = appleCacheRoot.appendingPathComponent("25E246", isDirectory: true)
        let runtimeDirectory = bucketDirectory.appendingPathComponent("CACHE-A", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
        try Data("runtime".utf8).write(to: runtimeDirectory.appendingPathComponent("payload.bin"))
        try setModificationDate(daysAgo: 60, for: runtimeDirectory)

        let runtimeState = MockLocalAICacheRuntimeState(
            loadedASRLocalModelID: LocalTranscriptionModel.parakeetTdt06BV3.rawValue,
            modelState: .loaded,
            isASRInUse: false,
            isASRResidentInMemory: true,
        )
        let service = LocalAICacheMaintenanceService(
            runtimeState: runtimeState,
            fileManager: .default,
            appleRuntimeCacheDirectoryProvider: { appleCacheRoot },
        )

        let preview = try await service.computeCleanupPreview(olderThanDays: 30)

        XCTAssertEqual(preview.appleRuntimeCount, 0)
    }

    func testPerformCleanup_WhenCandidateEligible_RemovesCacheDirectory() async throws {
        let rootDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let appleCacheRoot = rootDirectory.appendingPathComponent("AppleCache", isDirectory: true)
        let bucketDirectory = appleCacheRoot.appendingPathComponent("25E246", isDirectory: true)
        let runtimeDirectory = bucketDirectory.appendingPathComponent("CACHE-A", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
        try Data(repeating: 0xab, count: 32).write(to: runtimeDirectory.appendingPathComponent("payload.bin"))
        try setModificationDate(daysAgo: 60, for: runtimeDirectory)

        let runtimeState = MockLocalAICacheRuntimeState()
        let service = LocalAICacheMaintenanceService(
            runtimeState: runtimeState,
            fileManager: .default,
            appleRuntimeCacheDirectoryProvider: { appleCacheRoot },
        )

        let preview = try await service.computeCleanupPreview(olderThanDays: 30)
        let result = try await service.performCleanup(preview: preview)

        XCTAssertEqual(result.deletedAppleRuntimeCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: runtimeDirectory.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalAICacheMaintenanceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func setModificationDate(daysAgo: Int, for url: URL) throws {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date.distantPast
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
}

@MainActor
private final class MockLocalAICacheRuntimeState: LocalAICacheRuntimeStateProviding {
    var loadedASRLocalModelID: String?
    var modelState: MeetingAssistantCoreDomain.ModelState
    var isASRInUse: Bool
    var isASRResidentInMemory: Bool

    init(
        loadedASRLocalModelID: String? = nil,
        modelState: MeetingAssistantCoreDomain.ModelState = .unloaded,
        isASRInUse: Bool = false,
        isASRResidentInMemory: Bool = false,
    ) {
        self.loadedASRLocalModelID = loadedASRLocalModelID
        self.modelState = modelState
        self.isASRInUse = isASRInUse
        self.isASRResidentInMemory = isASRResidentInMemory
    }
}

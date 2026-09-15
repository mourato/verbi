import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure
import os.log

@MainActor
protocol LocalAICacheRuntimeStateProviding: AnyObject {
    var loadedASRLocalModelID: String? { get }
    var modelState: FluidAIModelManager.ModelState { get }
    var isASRInUse: Bool { get }
    var isASRResidentInMemory: Bool { get }
}

extension FluidAIModelManager: LocalAICacheRuntimeStateProviding {}

public enum LocalAICacheCleanupKind: String, Hashable, Sendable {
    case appleRuntime
}

public struct LocalAICacheCleanupCandidate: Hashable, Sendable {
    public let url: URL
    public let byteSize: Int64
    public let kind: LocalAICacheCleanupKind

    public init(url: URL, byteSize: Int64, kind: LocalAICacheCleanupKind) {
        self.url = url
        self.byteSize = byteSize
        self.kind = kind
    }
}

public struct LocalAICacheCleanupPreview: Hashable, Sendable {
    public let retentionDays: Int
    public let candidates: [LocalAICacheCleanupCandidate]

    public init(retentionDays: Int, candidates: [LocalAICacheCleanupCandidate]) {
        self.retentionDays = retentionDays
        self.candidates = candidates
    }

    public var candidateCount: Int {
        candidates.count
    }

    public var totalBytes: Int64 {
        candidates.reduce(0) { $0 + $1.byteSize }
    }

    public var appleRuntimeCount: Int {
        candidates.count(where: { $0.kind == .appleRuntime })
    }

    public var totalAppleRuntimeBytes: Int64 {
        candidates.filter { $0.kind == .appleRuntime }.reduce(0) { $0 + $1.byteSize }
    }
}

public struct LocalAICacheCleanupResult: Hashable, Sendable {
    public let deletedCandidates: Int
    public let deletedBytes: Int64
    public let deletedAppleRuntimeCount: Int

    public init(
        deletedCandidates: Int,
        deletedBytes: Int64,
        deletedAppleRuntimeCount: Int
    ) {
        self.deletedCandidates = deletedCandidates
        self.deletedBytes = deletedBytes
        self.deletedAppleRuntimeCount = deletedAppleRuntimeCount
    }
}

@MainActor
public final class LocalAICacheMaintenanceService {
    public static let shared = LocalAICacheMaintenanceService()

    private let runtimeState: any LocalAICacheRuntimeStateProviding
    private let fileManager: FileManager
    private let appleRuntimeCacheDirectoryProvider: () -> URL
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "LocalAICacheMaintenance")

    init(
        runtimeState: (any LocalAICacheRuntimeStateProviding)? = nil,
        fileManager: FileManager = .default,
        appleRuntimeCacheDirectoryProvider: (() -> URL)? = nil
    ) {
        self.runtimeState = runtimeState ?? FluidAIModelManager.shared
        self.fileManager = fileManager
        self.appleRuntimeCacheDirectoryProvider = appleRuntimeCacheDirectoryProvider ?? {
            AppIdentity.cachesBaseDirectory(fileManager: .default)
                .appendingPathComponent(AppIdentity.bundleIdentifier, isDirectory: true)
                .appendingPathComponent("com.apple.e5rt.e5bundlecache", isDirectory: true)
        }
    }

    public func computeCleanupPreview(olderThanDays days: Int) throws -> LocalAICacheCleanupPreview {
        let retentionDays = max(1, days)
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        let appleRuntimeCacheDirectory = appleRuntimeCacheDirectoryProvider().standardizedFileURL
        let runtimeSnapshot = runtimeSnapshot()

        let candidates: [LocalAICacheCleanupCandidate] = if runtimeSnapshot.hasActiveRuntime {
            []
        } else {
            appleRuntimeCandidates(
                cacheDirectory: appleRuntimeCacheDirectory,
                cutoffDate: cutoffDate
            )
            .sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
        }

        return LocalAICacheCleanupPreview(retentionDays: retentionDays, candidates: candidates)
    }

    public func performCleanup(olderThanDays days: Int) async throws -> LocalAICacheCleanupResult {
        let preview = try await computeCleanupPreview(olderThanDays: days)
        return try await performCleanup(preview: preview)
    }

    public func performCleanup(preview: LocalAICacheCleanupPreview) throws -> LocalAICacheCleanupResult {
        guard !preview.candidates.isEmpty else {
            return LocalAICacheCleanupResult(
                deletedCandidates: 0,
                deletedBytes: 0,
                deletedAppleRuntimeCount: 0
            )
        }

        let appleRoot = appleRuntimeCacheDirectoryProvider().standardizedFileURL.path
        var deletedCandidates = 0
        var deletedBytes: Int64 = 0
        var deletedAppleRuntimeCount = 0

        for candidate in preview.candidates where isAllowedCandidate(candidate.url, appleRoot: appleRoot) {
            guard fileManager.fileExists(atPath: candidate.url.path) else { continue }

            try fileManager.removeItem(at: candidate.url)
            deletedCandidates += 1
            deletedBytes += candidate.byteSize
            deletedAppleRuntimeCount += 1
        }

        removeEmptyDirectoriesIfNeeded(at: URL(fileURLWithPath: appleRoot, isDirectory: true))

        if deletedCandidates > 0 {
            logger.info(
                "Cleaned local AI caches: count=\(deletedCandidates, privacy: .public) bytes=\(deletedBytes, privacy: .public)"
            )
        }

        return LocalAICacheCleanupResult(
            deletedCandidates: deletedCandidates,
            deletedBytes: deletedBytes,
            deletedAppleRuntimeCount: deletedAppleRuntimeCount
        )
    }

    private func runtimeSnapshot() -> LocalAICacheRuntimeSnapshot {
        LocalAICacheRuntimeSnapshot(
            loadedASRLocalModelID: runtimeState.loadedASRLocalModelID,
            modelState: runtimeState.modelState,
            isASRInUse: runtimeState.isASRInUse,
            isASRResidentInMemory: runtimeState.isASRResidentInMemory
        )
    }

    private func appleRuntimeCandidates(
        cacheDirectory: URL,
        cutoffDate: Date
    ) -> [LocalAICacheCleanupCandidate] {
        appleRuntimeLeafDirectories(in: cacheDirectory).compactMap { directory in
            guard isOlderThanCutoff(directory, cutoffDate: cutoffDate) else { return nil }
            return LocalAICacheCleanupCandidate(
                url: directory,
                byteSize: directoryByteSize(at: directory),
                kind: .appleRuntime
            )
        }
    }

    private func appleRuntimeLeafDirectories(in rootDirectory: URL) -> [URL] {
        guard fileManager.fileExists(atPath: rootDirectory.path) else { return [] }
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey]
        let groups = (try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        )) ?? []

        var candidates: [URL] = []

        for group in groups where isDirectory(group) {
            let children = (try? fileManager.contentsOfDirectory(
                at: group,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles]
            )) ?? []
            let childDirectories = children.filter(isDirectory)

            if childDirectories.isEmpty {
                candidates.append(group)
            } else {
                candidates.append(contentsOf: childDirectories)
            }
        }

        return candidates
    }

    private func isAllowedCandidate(_ url: URL, appleRoot: String) -> Bool {
        let standardizedPath = url.standardizedFileURL.path
        return standardizedPath == appleRoot
            || standardizedPath.hasPrefix(appleRoot + "/")
    }

    private func isOlderThanCutoff(_ url: URL, cutoffDate: Date) -> Bool {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        let referenceDate = values?.contentModificationDate ?? values?.creationDate
        return referenceDate == nil || referenceDate! < cutoffDate
    }

    private func directoryByteSize(at url: URL) -> Int64 {
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]

        if !isDirectory(url) {
            let values = try? url.resourceValues(forKeys: Set(resourceKeys))
            return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: Set(resourceKeys))
            guard values?.isDirectory != true else { continue }
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }

    private func isDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory == true
    }

    private func removeEmptyDirectoriesIfNeeded(at rootDirectory: URL) {
        guard fileManager.fileExists(atPath: rootDirectory.path) else { return }

        let contents = (try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for child in contents where isDirectory(child) {
            removeEmptyDirectoriesIfNeeded(at: child)
        }

        let remaining = (try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        if remaining.isEmpty {
            try? fileManager.removeItem(at: rootDirectory)
        }
    }
}

private struct LocalAICacheRuntimeSnapshot {
    let loadedASRLocalModelID: String?
    let modelState: FluidAIModelManager.ModelState
    let isASRInUse: Bool
    let isASRResidentInMemory: Bool

    var hasActiveRuntime: Bool {
        isASRInUse || isASRResidentInMemory || modelState == .downloading || modelState == .loading || modelState == .loaded
    }
}

import CoreData
import Foundation
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

extension FileSystemStorageService {
    /// Unreferenced recordings the orphan sweep may delete. Pure decision
    /// step (no deletion) so tests can drive it end to end with temp
    /// directories and fakes.
    static func orphanedFilesToDelete(
        in recordingsDir: URL,
        knownAudioPaths: Set<String>,
        stores: InterruptedRecordingRecovery.Stores,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) -> [URL] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: recordingsDir,
            includingPropertiesForKeys: [.creationDateKey]
        ) else {
            return []
        }

        let knownStandardized = Set(knownAudioPaths.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        })

        return files
            .filter { ["wav", "m4a"].contains($0.pathExtension.lowercased()) }
            .filter { fileURL in
                let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
                let createdAt = attributes?[.creationDate] as? Date
                return InterruptedRecordingRecovery.shouldDeleteOrphanedFile(
                    filename: fileURL.lastPathComponent,
                    createdAt: createdAt,
                    isReferenced: knownStandardized.contains(fileURL.standardizedFileURL.path),
                    pendingFilenames: stores.pending,
                    dismissedFilenames: stores.dismissed,
                    now: now
                )
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func cleanupOrphanedRecordings() async throws {
        let recordingsDir = recordingsDirectory
        let stores = InterruptedRecordingRecovery.loadStores()
        let currentPriority = Task.currentPriority

        try await Task.detached(priority: currentPriority) { [self] in
            let allMetadata = try await loadAllMetadata()
            let knownAudioPaths = Set(allMetadata.compactMap(\.audioFilePath))
            let fileManager = FileManager.default

            var deletedCount = 0

            for file in Self.orphanedFilesToDelete(
                in: recordingsDir,
                knownAudioPaths: knownAudioPaths,
                stores: stores,
                fileManager: fileManager
            ) {
                do {
                    try fileManager.removeItem(at: file)
                    deletedCount += 1
                    AppLogger.info(
                        "Deleted orphaned recording",
                        category: .databaseManager,
                        extra: ["filename": file.lastPathComponent]
                    )
                } catch {
                    AppLogger.error("Failed to delete orphan", category: .databaseManager, error: error)
                }
            }

            if deletedCount > 0 {
                AppLogger.info(
                    "Orphan cleanup completed",
                    category: .databaseManager,
                    extra: ["deletedCount": deletedCount]
                )
            }
        }.value
    }
}

import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

extension FileSystemStorageService {
    // MARK: - Legacy JSON migration

    /// One-time migration for legacy JSON transcriptions into Core Data.
    ///
    /// This is designed to be idempotent:
    /// - Transcriptions are upserted into Core Data by `id`.
    /// - Migrated JSON files are moved to `transcripts/legacy-json-archive/`.
    /// - The `UserDefaults` checkpoint is only marked complete when there are no
    ///   remaining `.json` files in the legacy directory root.
    public func migrateLegacyJSONTranscriptionsToCoreDataIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: Keys.didMigrateLegacyJSONTranscriptionsToCoreDataV1) else {
            return
        }

        let legacyDirectory = legacyTranscriptsDirectory
        let archiveDirectory = legacyDirectory.appendingPathComponent("legacy-json-archive", isDirectory: true)
        guard createArchiveDirectoryIfNeeded(archiveDirectory) else {
            return
        }

        let legacyJSONFiles = enumerateLegacyJSONFiles(in: legacyDirectory)
        guard !legacyJSONFiles.isEmpty else {
            UserDefaults.standard.set(true, forKey: Keys.didMigrateLegacyJSONTranscriptionsToCoreDataV1)
            return
        }

        let decoder = makeLegacyDecoder()
        let migrationResult = await migrateLegacyFiles(
            legacyJSONFiles,
            decoder: decoder,
            archiveDirectory: archiveDirectory
        )

        let remainingJSONFiles = enumerateLegacyJSONFiles(in: legacyDirectory)
        if remainingJSONFiles.isEmpty {
            UserDefaults.standard.set(true, forKey: Keys.didMigrateLegacyJSONTranscriptionsToCoreDataV1)
        }

        AppLogger.info(
            "Legacy JSON → Core Data migration finished",
            category: .databaseManager,
            extra: [
                "migratedCount": "\(migrationResult.migratedCount)",
                "failedCount": "\(migrationResult.failedCount)"
            ]
        )
    }

    private func createArchiveDirectoryIfNeeded(_ archiveDirectory: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
            return true
        } catch {
            AppLogger.error(
                "Failed to create legacy JSON archive directory",
                category: .databaseManager,
                error: error
            )
            return false
        }
    }

    private func makeLegacyDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func enumerateLegacyJSONFiles(in directory: URL) -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension.lowercased() == "json" }
        } catch {
            AppLogger.error(
                "Failed to enumerate legacy transcripts directory",
                category: .databaseManager,
                error: error
            )
            return []
        }
    }

    private func migrateLegacyFiles(
        _ files: [URL],
        decoder: JSONDecoder,
        archiveDirectory: URL
    ) async -> (migratedCount: Int, failedCount: Int) {
        var migratedCount = 0
        var failedCount = 0

        for fileURL in files {
            do {
                try await migrateLegacyFile(
                    at: fileURL,
                    decoder: decoder,
                    archiveDirectory: archiveDirectory
                )
                migratedCount += 1
            } catch {
                failedCount += 1
                AppLogger.error(
                    "Failed to migrate legacy JSON transcription",
                    category: .databaseManager,
                    error: error,
                    extra: ["filename": fileURL.lastPathComponent]
                )
            }
        }

        return (migratedCount, failedCount)
    }

    private func migrateLegacyFile(
        at fileURL: URL,
        decoder: JSONDecoder,
        archiveDirectory: URL
    ) async throws {
        let data = try Data(contentsOf: fileURL)
        let legacy = try decoder.decode(Transcription.self, from: data)
        let entity = Self.convertToEntity(legacy)

        try await coreDataTranscriptionRepository.saveTranscription(entity)

        let destinationURL = archiveDirectory.appendingPathComponent(fileURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.moveItem(at: fileURL, to: destinationURL)
    }
}

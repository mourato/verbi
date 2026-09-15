import CoreData
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

public extension FileSystemStorageService {
    internal struct RetentionPreviewContext {
        let retentionDays: Int
        let cutoffDate: Date
        let recordingsDir: URL
        let audioPathsToKeep: Set<String>
        let audioPathsEligibleForDeletion: Set<String>
        let transcriptionCandidates: [RetentionCleanupTranscriptionCandidate]
    }

    internal func setupDirectories() {
        do {
            try FileManager.default.createDirectory(at: defaultRecordingsDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: legacyTranscriptsDirectory, withIntermediateDirectories: true)
        } catch {
            AppLogger.fault("Failed to create storage directories", category: .databaseManager, error: error)
        }

        Task { [weak self] in
            try? await self?.cleanupStaleDictationCheckpoints()
        }
    }

    func createRecordingURL(for meeting: Meeting, type: RecordingType) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: meeting.startTime)
        let appName = InputSanitizer.sanitizeFilename(meeting.app.rawValue)

        var filename = "\(appName)_\(timestamp)"
        let formatRaw = UserDefaults.standard.string(forKey: AppSettingsStore.PostProcessingKeys.audioFormat)
        let format = formatRaw.flatMap { AppSettingsStore.AudioFormat(rawValue: $0) } ?? .wav
        let fileExtension = format.fileExtension

        switch type {
        case .microphone:
            filename += "_mic.\(fileExtension)"
        case .system:
            filename += "_sys.wav"
        case .merged:
            filename += ".\(fileExtension)"
        }

        return recordingsDirectory.appendingPathComponent(filename)
    }

    func cleanupTemporaryFiles(urls: [URL]) {
        for url in urls {
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                    AppLogger.debug(
                        "Deleted temporary file",
                        category: .databaseManager,
                        extra: ["filename": url.lastPathComponent]
                    )
                }
            } catch {
                AppLogger.error(
                    "Failed to delete file",
                    category: .databaseManager,
                    error: error,
                    extra: ["filename": url.lastPathComponent]
                )
            }
        }
    }

    func saveTranscription(_ transcription: Transcription) async throws {
        await coreDataStack.sanitizeMockTranscriptionArtifactsIfNeeded()
        await coreDataStack.sanitizeMeetingOnlyPresentationDataIfNeeded(
            checkpointKey: Keys.didSanitizeNonMeetingPresentationDataV1
        )
        await coreDataStack.backfillModelPerformanceAttemptsIfNeeded()

        let entity = Self.convertToEntity(transcription)
        try await coreDataTranscriptionRepository.saveTranscription(entity)
        AppLogger.info("Saved transcription (Core Data)", category: .databaseManager, extra: ["id": transcription.id.uuidString])
    }

    func saveModelPerformanceAttempt(_ attempt: ModelPerformanceAttempt) async throws {
        await coreDataStack.sanitizeMockTranscriptionArtifactsIfNeeded()
        await coreDataStack.sanitizeMeetingOnlyPresentationDataIfNeeded(
            checkpointKey: Keys.didSanitizeNonMeetingPresentationDataV1
        )
        await coreDataStack.backfillModelPerformanceAttemptsIfNeeded()

        try await coreDataTranscriptionRepository.saveModelPerformanceAttempt(attempt)
        AppLogger.info(
            "Saved model performance attempt",
            category: .databaseManager,
            extra: ["attemptID": attempt.id.uuidString, "transcriptionID": attempt.transcriptionID.uuidString]
        )
    }

    func loadTranscriptions() async throws -> [Transcription] {
        await coreDataStack.sanitizeMockTranscriptionArtifactsIfNeeded()
        await coreDataStack.sanitizeMeetingOnlyPresentationDataIfNeeded(
            checkpointKey: Keys.didSanitizeNonMeetingPresentationDataV1
        )
        await coreDataStack.backfillModelPerformanceAttemptsIfNeeded()

        let entities = try await coreDataTranscriptionRepository.fetchAllTranscriptions()
        let models = entities.map(Self.convertToModel)
        AppLogger.info("Loaded transcriptions (Core Data)", category: .databaseManager, extra: ["count": models.count])
        return models
    }

    func loadAllMetadata() async throws -> [TranscriptionMetadata] {
        try await loadMetadata(
            matching: TranscriptionMetadataQuery(
                sourceFilter: .all,
                dateFilter: .allEntries,
                searchText: "",
                appRawValue: nil
            )
        )
    }

    func loadMetadata(matching query: TranscriptionMetadataQuery) async throws -> [TranscriptionMetadata] {
        await coreDataStack.sanitizeMockTranscriptionArtifactsIfNeeded()
        await coreDataStack.sanitizeMeetingOnlyPresentationDataIfNeeded(
            checkpointKey: Keys.didSanitizeNonMeetingPresentationDataV1
        )
        await coreDataStack.backfillModelPerformanceAttemptsIfNeeded()

        return try await coreDataStack.performBackgroundTask { context in
            let request = TranscriptionMO.fetchRequest()
            request.fetchBatchSize = 100
            request.relationshipKeyPathsForPrefetching = ["meeting"]
            request.predicate = Self.buildMetadataPredicate(for: query)
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: !query.sortNewestFirst)]
            if let limit = query.limit {
                request.fetchLimit = max(limit, 0)
            }

            let results = try context.fetch(request)
            return results.map(Self.convertToMetadata)
        }
    }

    func loadModelPerformanceAttempts(matching query: ModelPerformanceAttemptQuery) async throws -> [ModelPerformanceAttempt] {
        await coreDataStack.sanitizeMockTranscriptionArtifactsIfNeeded()
        await coreDataStack.sanitizeMeetingOnlyPresentationDataIfNeeded(
            checkpointKey: Keys.didSanitizeNonMeetingPresentationDataV1
        )
        await coreDataStack.backfillModelPerformanceAttemptsIfNeeded()

        return try await coreDataTranscriptionRepository.fetchModelPerformanceAttempts(matching: query)
    }

    func loadTranscription(by id: UUID) async throws -> Transcription? {
        await coreDataStack.sanitizeMockTranscriptionArtifactsIfNeeded()
        await coreDataStack.sanitizeMeetingOnlyPresentationDataIfNeeded(
            checkpointKey: Keys.didSanitizeNonMeetingPresentationDataV1
        )
        await coreDataStack.backfillModelPerformanceAttemptsIfNeeded()

        guard let entity = try await coreDataTranscriptionRepository.fetchTranscription(by: id) else {
            return nil
        }
        return Self.convertToModel(entity)
    }

    func deleteTranscription(by id: UUID) async throws {
        try await coreDataTranscriptionRepository.deleteTranscription(by: id)
        AppLogger.info("Deleted transcription (Core Data)", category: .databaseManager, extra: ["id": id.uuidString])
    }

    func cleanupOldTranscriptions(olderThanDays days: Int) async throws {
        let preview = try await computeRetentionCleanupPreview(olderThanDays: days)
        _ = try await performRetentionCleanup(preview: preview)
        try? await cleanupOrphanedRecordings()
    }

    func computeRetentionCleanupPreview(olderThanDays days: Int) async throws -> RetentionCleanupPreview {
        let currentPriority = Task.currentPriority

        return try await Task.detached(priority: currentPriority) { [self] in
            let retentionDays = max(1, days)
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()

            let allMetadata = try await loadAllMetadata()
            let metadataWithAudioToDelete = allMetadata.filter { $0.createdAt < cutoffDate }
            let metadataWithAudioToKeep = allMetadata.filter { $0.createdAt >= cutoffDate }

            let context = RetentionPreviewContext(
                retentionDays: retentionDays,
                cutoffDate: cutoffDate,
                recordingsDir: recordingsDirectory.standardizedFileURL,
                audioPathsToKeep: Self.standardizedAudioPaths(from: metadataWithAudioToKeep),
                audioPathsEligibleForDeletion: Self.standardizedAudioPaths(from: metadataWithAudioToDelete),
                transcriptionCandidates: []
            )

            return Self.computeRetentionCleanupPreviewSync(context: context)
        }.value
    }

    internal static func standardizedAudioPaths(from transcriptions: [TranscriptionMetadata]) -> Set<String> {
        Set(transcriptions.compactMap { meta in
            guard let path = meta.audioFilePath else { return nil }
            return standardizePath(path: path)
        })
    }

    func cleanupStaleDictationCheckpoints() async throws {
        try await cleanupStaleTranscriptionCheckpoints()
    }

    func cleanupStaleTranscriptionCheckpoints() async throws {
        try await coreDataStack.performBackgroundTask { context in
            let request = TranscriptionMO.fetchRequest()
            request.predicate = NSPredicate(
                format: "lifecycleStateRawValue IN %@",
                [TranscriptionLifecycleState.partial.rawValue, TranscriptionLifecycleState.finalizing.rawValue]
            )

            let results = try context.fetch(request)
            guard !results.isEmpty else { return }

            for transcription in results {
                context.delete(transcription)
            }

            try context.save()
        }
    }

    internal static func computeRetentionCleanupPreviewSync(context: RetentionPreviewContext) -> RetentionCleanupPreview {
        let fileManager = FileManager.default
        var audioURLsToDelete = collectAudioURLsFromRetentionMetadata(
            paths: context.audioPathsEligibleForDeletion,
            recordingsDirectoryPath: context.recordingsDir.path
        )

        let files = listRecordingFiles(in: context.recordingsDir, fileManager: fileManager)
        for fileURL in files {
            guard shouldDeleteRecordingFile(
                fileURL,
                keepPaths: context.audioPathsToKeep,
                cutoffDate: context.cutoffDate
            ) else {
                continue
            }
            audioURLsToDelete.insert(fileURL.standardizedFileURL)
        }

        let audioFiles = computeAudioCandidates(
            audioURLsToDelete: audioURLsToDelete,
            fileByteSizeIfExists: fileByteSizeIfExists,
            fileManager: fileManager
        )
        let sortedTranscriptions = context.transcriptionCandidates.sorted { $0.id.uuidString < $1.id.uuidString }

        return RetentionCleanupPreview(
            retentionDays: context.retentionDays,
            audioFiles: audioFiles,
            transcriptions: sortedTranscriptions
        )
    }

    internal static func computeAudioCandidates(
        audioURLsToDelete: Set<URL>,
        fileByteSizeIfExists: (URL) -> Int64?,
        fileManager: FileManager
    ) -> [RetentionCleanupAudioCandidate] {
        var audioFiles: [RetentionCleanupAudioCandidate] = []
        audioFiles.reserveCapacity(audioURLsToDelete.count)

        for url in audioURLsToDelete where fileManager.fileExists(atPath: url.path) {
            let bytes = fileByteSizeIfExists(url) ?? 0
            audioFiles.append(RetentionCleanupAudioCandidate(url: url, byteSize: bytes))
        }

        audioFiles.sort { $0.url.lastPathComponent < $1.url.lastPathComponent }
        return audioFiles
    }

    func performRetentionCleanup(preview: RetentionCleanupPreview) async throws -> RetentionCleanupResult {
        let audioToDelete = preview.audioFiles.map(\.url)
        let recordingsDirPath = recordingsDirectory.standardizedFileURL.path
        let deletedTranscriptions = 0
        let currentPriority = Task.currentPriority

        let deletedAudio = try await Task.detached(priority: currentPriority) {
            let fileManager = FileManager.default
            var deletedAudio = 0
            let normalizedRecordingsDir = Self.normalizeDirectoryPath(recordingsDirPath)

            for url in audioToDelete
                where Self.isUnderDirectory(url, directoryPath: normalizedRecordingsDir) && Self.isAllowedAudioFile(url)
            {
                if try Self.removeIfExists(url, fileManager: fileManager) {
                    deletedAudio += 1
                }
            }

            return deletedAudio
        }.value

        if deletedAudio > 0 || deletedTranscriptions > 0 {
            AppLogger.info(
                "Retention cleanup completed",
                category: .databaseManager,
                extra: [
                    "deletedAudioCount": "\(deletedAudio)",
                    "deletedTranscriptionCount": "\(deletedTranscriptions)"
                ]
            )
        }

        return RetentionCleanupResult(
            deletedAudioCount: deletedAudio,
            deletedTranscriptionCount: deletedTranscriptions
        )
    }

    func cleanupOrphanedRecordings() async throws {
        let recordingsDir = recordingsDirectory
        let currentPriority = Task.currentPriority

        try await Task.detached(priority: currentPriority) { [self] in
            let allMetadata = try await loadAllMetadata()
            let knownAudioPaths = Set(allMetadata.compactMap(\.audioFilePath))
            let fileManager = FileManager.default
            guard let files = try? fileManager.contentsOfDirectory(
                at: recordingsDir,
                includingPropertiesForKeys: [.creationDateKey]
            ) else {
                return
            }

            var deletedCount = 0

            for file in files where ["wav", "m4a"].contains(file.pathExtension.lowercased()) {
                guard !knownAudioPaths.contains(file.path) else { continue }

                if let attr = try? fileManager.attributesOfItem(atPath: file.path),
                   let creationDate = attr[.creationDate] as? Date,
                   Date().timeIntervalSince(creationDate) > 86400
                {
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

    internal static func standardizePath(path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    internal static func normalizeDirectoryPath(_ path: String) -> String {
        var normalized = path
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }

    internal static func buildMetadataPredicate(for query: TranscriptionMetadataQuery) -> NSPredicate? {
        var predicates: [NSPredicate] = []

        if !query.includeNonVisibleLifecycleStates {
            let visibleStates = [TranscriptionLifecycleState.completed.rawValue, TranscriptionLifecycleState.failed.rawValue]
            predicates.append(NSPredicate(format: "lifecycleStateRawValue IN %@", visibleStates))
        }

        switch query.sourceFilter {
        case .all:
            break
        case .dictations:
            predicates.append(
                NSCompoundPredicate(orPredicateWithSubpredicates: [
                    NSPredicate(format: "meeting.capturePurposeRawValue == %@", CapturePurpose.dictation.rawValue),
                    NSPredicate(
                        format: "meeting.capturePurposeRawValue == nil AND meeting.appRawValue == %@",
                        MeetingApp.unknown.rawValue
                    )
                ])
            )
        case .meetings:
            predicates.append(
                NSCompoundPredicate(orPredicateWithSubpredicates: [
                    NSPredicate(format: "meeting.capturePurposeRawValue == %@", CapturePurpose.meeting.rawValue),
                    NSPredicate(
                        format: "meeting.capturePurposeRawValue == nil AND meeting.appRawValue != %@",
                        MeetingApp.unknown.rawValue
                    )
                ])
            )
        }

        if query.dateFilter != .allEntries {
            let range = query.dateFilter.dateRange
            predicates.append(
                NSPredicate(
                    format: "createdAt >= %@ AND createdAt < %@",
                    range.start as NSDate,
                    range.end as NSDate
                )
            )
        }

        if let appRawValue = query.appRawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !appRawValue.isEmpty
        {
            predicates.append(NSPredicate(format: "meeting.appRawValue == %@", appRawValue))
        }

        let trimmedSearch = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty {
            let searchPredicates = [
                NSPredicate(format: "text CONTAINS[cd] %@", trimmedSearch),
                NSPredicate(format: "meeting.title CONTAINS[cd] %@", trimmedSearch),
                NSPredicate(format: "meeting.appDisplayName CONTAINS[cd] %@", trimmedSearch),
                NSPredicate(format: "meeting.appRawValue CONTAINS[cd] %@", trimmedSearch)
            ]
            predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: searchPredicates))
        }

        guard !predicates.isEmpty else { return nil }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    private static func collectAudioURLsFromRetentionMetadata(
        paths: Set<String>,
        recordingsDirectoryPath: String
    ) -> Set<URL> {
        var audioURLsToDelete: Set<URL> = []
        audioURLsToDelete.reserveCapacity(paths.count)

        for audioPath in paths where isPathInsideRecordingsDirectory(audioPath, recordingsDirectoryPath: recordingsDirectoryPath) {
            let url = URL(fileURLWithPath: audioPath).standardizedFileURL
            guard isAllowedAudioFile(url) else { continue }
            audioURLsToDelete.insert(url)
        }

        return audioURLsToDelete
    }

    private static func listRecordingFiles(in recordingsDir: URL, fileManager: FileManager) -> [URL] {
        let resourceKeys: [URLResourceKey] = [
            .contentModificationDateKey,
            .creationDateKey,
            .fileSizeKey,
            .isDirectoryKey
        ]

        return (try? fileManager.contentsOfDirectory(
            at: recordingsDir,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private static func shouldDeleteRecordingFile(
        _ fileURL: URL,
        keepPaths: Set<String>,
        cutoffDate: Date
    ) -> Bool {
        let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey, .isDirectoryKey])
        if values?.isDirectory == true || !isAllowedAudioFile(fileURL) {
            return false
        }

        let standardizedPath = fileURL.standardizedFileURL.path
        if keepPaths.contains(standardizedPath) {
            return false
        }

        let referenceDate = values?.contentModificationDate ?? values?.creationDate
        return referenceDate == nil || referenceDate! < cutoffDate
    }

    private static func fileByteSizeIfExists(_ url: URL) -> Int64? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = values?.fileSize {
            return Int64(fileSize)
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes?[.size] as? NSNumber {
            return size.int64Value
        }
        return nil
    }

    private static func isPathInsideRecordingsDirectory(_ path: String, recordingsDirectoryPath: String) -> Bool {
        let normalizedRecordings = normalizeDirectoryPath(recordingsDirectoryPath)
        let normalizedPath = normalizeDirectoryPath(path)
        return normalizedPath == normalizedRecordings || normalizedPath.hasPrefix(normalizedRecordings + "/")
    }

    private static func isAllowedAudioFile(_ url: URL) -> Bool {
        ["m4a", "wav"].contains(url.pathExtension.lowercased())
    }

    private static func isUnderDirectory(_ url: URL, directoryPath: String) -> Bool {
        let standardized = url.standardizedFileURL.path
        return standardized == directoryPath || standardized.hasPrefix(directoryPath + "/")
    }

    private static func removeIfExists(_ url: URL, fileManager: FileManager) throws -> Bool {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
            return true
        }
        return false
    }
}

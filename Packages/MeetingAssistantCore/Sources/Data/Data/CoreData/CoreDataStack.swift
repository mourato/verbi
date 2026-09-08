import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain

// CoreDataStack - Stack thread-safe para gerenciamento de CoreData
// Seguindo Clean Architecture com isolamento de infraestrutura

import CoreData
import Foundation
import os.log

/// Stack CoreData thread-safe com suporte a operações em background
public final class CoreDataStack: Sendable {
    enum MigrationKeys {
        static let didSanitizeNonMeetingPresentationDataV1 = "storage.migrations.non_meeting_presentation_data_sanitized.v1"
        static let didRemoveMockTranscriptionArtifactsV1 = "storage.migrations.mock_transcription_artifacts_removed.v1"
        static let didBackfillModelPerformanceAttemptsV1 = "storage.migrations.model_performance_attempts_backfilled.v1"
    }

    private let persistentContainer: NSPersistentContainer
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "CoreData")

    public static let shared = CoreDataStack()

    /// Contexto principal para operações na main thread
    public var mainContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }

    /// Cria novo contexto em background para operações assíncronas
    public var backgroundContext: NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        context.shouldDeleteInaccessibleFaults = true
        return context
    }

    /// Inicializa o stack CoreData
    /// - Parameter name: Nome do modelo CoreData
    /// - Parameter inMemory: Se true, usa banco em memória (para testes)
    public init(name: String = AppIdentity.appSupportDirectoryName, inMemory: Bool = false) {
        let model = CoreDataModel.createManagedObjectModel()
        persistentContainer = NSPersistentContainer(name: name, managedObjectModel: model)
        let usesInMemoryStore = inMemory || AppIdentity.isRunningTests

        if usesInMemoryStore {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            description.shouldAddStoreAsynchronously = false
            persistentContainer.persistentStoreDescriptions = [description]
        } else {
            let storeURL = Self.persistentStoreURL(for: name)
            ensurePersistentStoreDirectoryExists(for: storeURL)
            Self.migrateLegacyPersistentStoreIfNeeded(currentStoreURL: storeURL, currentStoreName: name, logger: logger)

            let description = NSPersistentStoreDescription(url: storeURL)
            description.type = NSSQLiteStoreType
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            description.shouldAddStoreAsynchronously = false
            persistentContainer.persistentStoreDescriptions = [description]
        }

        var loadError: Error?
        persistentContainer.loadPersistentStores { [weak self] storeDescription, error in
            if let error {
                self?.logger.error("Failed to load persistent stores: \(error.localizedDescription)")
                loadError = error
                return
            }

            self?.logger.info("CoreData store loaded successfully: \(storeDescription.url?.absoluteString ?? "unknown")")
        }

        if let loadError {
            logger.fault("Primary persistent store failed. Falling back to in-memory store: \(loadError.localizedDescription)")
            Self.installInMemoryFallbackStore(on: persistentContainer, logger: logger)
        }

        // Configurar contexto principal
        mainContext.automaticallyMergesChangesFromParent = true
        mainContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        mainContext.shouldDeleteInaccessibleFaults = true
    }

    private static func persistentStoreURL(for storeName: String) -> URL {
        let baseDirectory = AppIdentity.appSupportBaseDirectory(fileManager: .default)
        return baseDirectory.appendingPathComponent("\(storeName).sqlite", isDirectory: false)
    }

    private static func migrateLegacyPersistentStoreIfNeeded(
        currentStoreURL: URL,
        currentStoreName: String,
        logger: Logger,
    ) {
        let fileManager = FileManager.default
        let appSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let currentDirectory = currentStoreURL.deletingLastPathComponent()

        var legacyCandidates: [URL] = []
        for legacyName in AppIdentity.legacyAppSupportDirectoryNames {
            let sameDirectoryLegacyStoreURL = currentDirectory
                .appendingPathComponent("\(legacyName).sqlite", isDirectory: false)
            let legacyDirectoryStoreURL = appSupportDirectory
                .appendingPathComponent(legacyName, isDirectory: true)
                .appendingPathComponent("\(legacyName).sqlite", isDirectory: false)
            if currentStoreName != legacyName {
                legacyCandidates.append(sameDirectoryLegacyStoreURL)
            }
            legacyCandidates.append(legacyDirectoryStoreURL)
        }

        var seenPaths = Set<String>()
        let legacyStoreURL = legacyCandidates.first { candidate in
            guard seenPaths.insert(candidate.path).inserted else { return false }
            return fileManager.fileExists(atPath: candidate.path)
        }

        guard let legacyStoreURL else {
            return
        }

        guard shouldMigrateLegacyStore(
            currentStoreURL: currentStoreURL,
            legacyStoreURL: legacyStoreURL,
            fileManager: fileManager,
        ) else {
            return
        }

        do {
            try backupStoreCluster(at: currentStoreURL, fileManager: fileManager)
            try replaceStoreCluster(sourceStoreURL: legacyStoreURL, destinationStoreURL: currentStoreURL, fileManager: fileManager)
            logger.notice("Migrated legacy CoreData store from \(legacyStoreURL.path, privacy: .public) to \(currentStoreURL.path, privacy: .public)")
        } catch {
            logger.error("Failed to migrate legacy CoreData store: \(error.localizedDescription)")
        }
    }

    private static func shouldMigrateLegacyStore(
        currentStoreURL: URL,
        legacyStoreURL: URL,
        fileManager: FileManager,
    ) -> Bool {
        guard fileManager.fileExists(atPath: legacyStoreURL.path) else {
            return false
        }

        guard fileManager.fileExists(atPath: currentStoreURL.path) else {
            return true
        }

        let currentMetrics = storeClusterMetrics(for: currentStoreURL, fileManager: fileManager)
        let legacyMetrics = storeClusterMetrics(for: legacyStoreURL, fileManager: fileManager)

        let currentLooksFresh = currentMetrics.sqliteBytes <= 65_536 && currentMetrics.walBytes == 0
        let legacyLooksRicher = legacyMetrics.sqliteBytes > currentMetrics.sqliteBytes || legacyMetrics.walBytes > 0
        return currentLooksFresh && legacyLooksRicher
    }

    private static func backupStoreCluster(at storeURL: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: storeURL.path) else {
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        for fileURL in storeClusterURLs(for: storeURL) where fileManager.fileExists(atPath: fileURL.path) {
            let backupURL = URL(fileURLWithPath: fileURL.path + ".pre-migration-\(timestamp)")
            try fileManager.copyItem(at: fileURL, to: backupURL)
        }
    }

    private static func replaceStoreCluster(
        sourceStoreURL: URL,
        destinationStoreURL: URL,
        fileManager: FileManager,
    ) throws {
        for destinationFileURL in storeClusterURLs(for: destinationStoreURL) where fileManager.fileExists(atPath: destinationFileURL.path) {
            try fileManager.removeItem(at: destinationFileURL)
        }

        for sourceFileURL in storeClusterURLs(for: sourceStoreURL) where fileManager.fileExists(atPath: sourceFileURL.path) {
            let suffix = sourceFileURL.path.replacingOccurrences(of: sourceStoreURL.path, with: "")
            let destinationFileURL = URL(fileURLWithPath: destinationStoreURL.path + suffix)
            try fileManager.copyItem(at: sourceFileURL, to: destinationFileURL)
        }
    }

    private static func storeClusterURLs(for storeURL: URL) -> [URL] {
        [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal"),
        ]
    }

    private static func storeClusterMetrics(for storeURL: URL, fileManager: FileManager) -> (sqliteBytes: UInt64, walBytes: UInt64) {
        (
            fileSize(of: storeURL, fileManager: fileManager),
            fileSize(of: URL(fileURLWithPath: storeURL.path + "-wal"), fileManager: fileManager),
        )
    }

    private static func fileSize(of fileURL: URL, fileManager: FileManager) -> UInt64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber
        else {
            return 0
        }
        return size.uint64Value
    }

    private func ensurePersistentStoreDirectoryExists(for storeURL: URL) {
        let directory = storeURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create CoreData store directory: \(directory.path, privacy: .public). Error: \(error.localizedDescription)")
        }
    }

    private static func installInMemoryFallbackStore(on container: NSPersistentContainer, logger: Logger) {
        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            do {
                try coordinator.remove(store)
            } catch {
                logger.error("Failed to remove persistent store before in-memory fallback: \(error.localizedDescription)")
            }
        }

        do {
            try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
            logger.notice("In-memory CoreData fallback store installed")
        } catch {
            logger.fault("Failed to install in-memory CoreData fallback store: \(error.localizedDescription)")
        }
    }

    /// Executa operação em background context de forma thread-safe
    /// - Parameter operation: Bloco assíncrono a executar
    /// - Returns: Resultado da operação
    public func performBackgroundTask<T: Sendable>(
        _ operation: @Sendable @escaping (NSManagedObjectContext) throws -> T,
    ) async throws -> T {
        let context = backgroundContext
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                do {
                    try continuation.resume(returning: operation(context))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Salva contexto de forma segura
    /// - Parameter context: Contexto a salvar
    public func save(context: NSManagedObjectContext) throws {
        guard context.hasChanges else { return }

        try context.save()

        if context == mainContext {
            logger.debug("Main context saved")
        } else {
            logger.debug("Background context saved")
        }
    }

    /// Salva contexto em background de forma assíncrona
    /// - Parameter context: Contexto a salvar
    public func saveAsync(context: NSManagedObjectContext) async throws {
        try await context.perform {
            try self.save(context: context)
        }
    }

    public func sanitizeMeetingOnlyPresentationDataIfNeeded(
        checkpointKey: String? = nil,
    ) async {
        let checkpointKey = checkpointKey ?? MigrationKeys.didSanitizeNonMeetingPresentationDataV1
        guard !UserDefaults.standard.bool(forKey: checkpointKey) else { return }

        do {
            let updatedCount = try await performBackgroundTask { context in
                try MeetingMO.sanitizeMeetingOnlyPresentationData(in: context)
            }

            UserDefaults.standard.set(true, forKey: checkpointKey)

            if updatedCount > 0 {
                logger.notice(
                    "Sanitized non-meeting title/calendar data for \(updatedCount, privacy: .public) persisted meetings",
                )
            }
        } catch {
            logger.error("Failed to sanitize non-meeting meeting presentation data: \(error.localizedDescription)")
        }
    }

    public func sanitizeMockTranscriptionArtifactsIfNeeded(
        checkpointKey: String? = nil,
    ) async {
        let checkpointKey = checkpointKey ?? MigrationKeys.didRemoveMockTranscriptionArtifactsV1
        guard !UserDefaults.standard.bool(forKey: checkpointKey) else { return }

        do {
            let removedCount = try await performBackgroundTask { context in
                try TranscriptionMO.removeMockArtifacts(in: context)
            }

            UserDefaults.standard.set(true, forKey: checkpointKey)

            if removedCount > 0 {
                logger.notice(
                    "Removed \(removedCount, privacy: .public) mock transcription artifacts from persistent history",
                )
            }
        } catch {
            logger.error("Failed to remove mock transcription artifacts: \(error.localizedDescription)")
        }
    }

    /// Reseta o stack (útil para testes)
    public func reset() throws {
        let stores = persistentContainer.persistentStoreCoordinator.persistentStores
        for store in stores {
            try persistentContainer.persistentStoreCoordinator.remove(store)
        }

        // Recarregar stores
        try persistentContainer.persistentStoreCoordinator.addPersistentStore(
            ofType: NSInMemoryStoreType,
            configurationName: nil,
            at: nil,
        )
    }
}

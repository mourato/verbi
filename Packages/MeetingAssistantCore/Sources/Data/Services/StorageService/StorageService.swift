import CoreData
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

// MARK: - Models

public enum RecordingType: String, Sendable {
    case microphone = "mic"
    case system = "sys"
    case merged
}

public struct RetentionCleanupAudioCandidate: Hashable, Sendable {
    public let url: URL
    public let byteSize: Int64

    public init(url: URL, byteSize: Int64) {
        self.url = url
        self.byteSize = byteSize
    }
}

public struct RetentionCleanupTranscriptionCandidate: Hashable, Sendable {
    public let id: UUID
    public let byteSize: Int64

    public init(id: UUID, byteSize: Int64) {
        self.id = id
        self.byteSize = byteSize
    }
}

public struct RetentionCleanupPreview: Hashable, Sendable {
    public let retentionDays: Int
    public let audioFiles: [RetentionCleanupAudioCandidate]
    public let transcriptions: [RetentionCleanupTranscriptionCandidate]

    public init(
        retentionDays: Int,
        audioFiles: [RetentionCleanupAudioCandidate],
        transcriptions: [RetentionCleanupTranscriptionCandidate]
    ) {
        self.retentionDays = retentionDays
        self.audioFiles = audioFiles
        self.transcriptions = transcriptions
    }

    public var audioCount: Int {
        audioFiles.count
    }

    public var transcriptionCount: Int {
        transcriptions.count
    }

    public var totalAudioBytes: Int64 {
        audioFiles.reduce(0) { $0 + $1.byteSize }
    }

    public var totalTranscriptionBytes: Int64 {
        transcriptions.reduce(0) { $0 + $1.byteSize }
    }
}

public struct RetentionCleanupResult: Hashable, Sendable {
    public let deletedAudioCount: Int
    public let deletedTranscriptionCount: Int

    public init(deletedAudioCount: Int, deletedTranscriptionCount: Int) {
        self.deletedAudioCount = deletedAudioCount
        self.deletedTranscriptionCount = deletedTranscriptionCount
    }
}

// MARK: - Protocol

public protocol StorageService: Sendable {
    /// Base directory for recordings.
    var recordingsDirectory: URL { get }

    /// Generate a URL for a new recording file.
    func createRecordingURL(for meeting: Meeting, type: RecordingType) -> URL

    /// Delete specified files.
    func cleanupTemporaryFiles(urls: [URL])

    /// Save a transcription to persistent storage.
    func saveTranscription(_ transcription: Transcription) async throws

    /// Save an immutable model-performance attempt linked to a transcription.
    func saveModelPerformanceAttempt(_ attempt: ModelPerformanceAttempt) async throws

    /// Load all transcriptions from storage.
    func loadTranscriptions() async throws -> [Transcription]

    /// Load lightweight metadata for all transcriptions.
    func loadAllMetadata() async throws -> [TranscriptionMetadata]

    /// Load lightweight metadata with server-side filters.
    func loadMetadata(matching query: TranscriptionMetadataQuery) async throws -> [TranscriptionMetadata]

    /// Load lightweight model-performance attempts with server-side filters.
    func loadModelPerformanceAttempts(matching query: ModelPerformanceAttemptQuery) async throws -> [ModelPerformanceAttempt]

    /// Load a specific transcription by its ID.
    func loadTranscription(by id: UUID) async throws -> Transcription?

    /// Delete a transcription by its ID.
    func deleteTranscription(by id: UUID) async throws

    /// Runs retention cleanup for old recordings on disk while preserving transcription records.
    func cleanupOldTranscriptions(olderThanDays days: Int) async throws

    /// Computes what would be deleted by retention cleanup (audio files only).
    func computeRetentionCleanupPreview(olderThanDays days: Int) async throws -> RetentionCleanupPreview

    /// Performs retention cleanup using a previously computed preview.
    func performRetentionCleanup(preview: RetentionCleanupPreview) async throws -> RetentionCleanupResult
}

// MARK: - Implementation

public final class FileSystemStorageService: StorageService {
    public static let shared = FileSystemStorageService()

    enum Keys {
        static let recordingsDirectory = "recordingsDirectory"
        static let didMigrateLegacyJSONTranscriptionsToCoreDataV1 = "storage.migrations.legacy_json_transcriptions_to_coredata.v1"
        static let didSanitizeNonMeetingPresentationDataV1 = "storage.migrations.non_meeting_presentation_data_sanitized.v1"
        static let didBackfillModelPerformanceAttemptsV1 = "storage.migrations.model_performance_attempts_backfilled.v1"
    }

    static func wordCount(for text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    public var recordingsDirectory: URL {
        let configuredPath = if honorsConfiguredRecordingDirectory {
            UserDefaults.standard.string(forKey: Keys.recordingsDirectory) ?? ""
        } else {
            ""
        }

        if !configuredPath.isEmpty {
            do {
                let validatedURL = try validateRecordingPath(configuredPath)
                try? FileManager.default.createDirectory(at: validatedURL, withIntermediateDirectories: true)
                return validatedURL
            } catch {
                AppLogger.error("Invalid recording directory path, using default", category: .databaseManager, error: error)
            }
        }
        return defaultRecordingsDirectory
    }

    let defaultRecordingsDirectory: URL
    let legacyTranscriptsDirectory: URL
    let coreDataStack: CoreDataStack
    let coreDataTranscriptionRepository: CoreDataTranscriptionStorageRepository
    let honorsConfiguredRecordingDirectory: Bool

    public convenience init(honorsConfiguredRecordingDirectory: Bool = !AppIdentity.isRunningTests) {
        self.init(
            honorsConfiguredRecordingDirectory: honorsConfiguredRecordingDirectory,
            coreDataStack: .shared
        )
    }

    public init(honorsConfiguredRecordingDirectory: Bool, coreDataStack: CoreDataStack) {
        self.honorsConfiguredRecordingDirectory = honorsConfiguredRecordingDirectory
        let baseDir = AppIdentity.appSupportBaseDirectory(fileManager: .default)
        defaultRecordingsDirectory = baseDir.appendingPathComponent("recordings", isDirectory: true)
        legacyTranscriptsDirectory = baseDir.appendingPathComponent("transcripts", isDirectory: true)
        self.coreDataStack = coreDataStack
        coreDataTranscriptionRepository = CoreDataTranscriptionStorageRepository(stack: coreDataStack)

        setupDirectories()
    }

    deinit {
        AppLogger.debug("FileSystemStorageService deinitialized", category: .databaseManager)
    }
}

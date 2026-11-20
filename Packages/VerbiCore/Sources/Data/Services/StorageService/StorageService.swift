import CoreData
import Foundation
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

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

public struct RetentionCleanupPreview: Hashable, Sendable {
    public let retentionDays: Int
    public let audioFiles: [RetentionCleanupAudioCandidate]

    public init(
        retentionDays: Int,
        audioFiles: [RetentionCleanupAudioCandidate]
    ) {
        self.retentionDays = retentionDays
        self.audioFiles = audioFiles
    }

    public var audioCount: Int {
        audioFiles.count
    }

    public var totalAudioBytes: Int64 {
        audioFiles.reduce(0) { $0 + $1.byteSize }
    }
}

public struct RetentionCleanupResult: Hashable, Sendable {
    public let deletedAudioCount: Int

    public init(deletedAudioCount: Int) {
        self.deletedAudioCount = deletedAudioCount
    }
}

public protocol StorageService: Sendable {
    var recordingsDirectory: URL { get }

    func createRecordingURL(for meeting: CaptureSession, type: RecordingType) -> URL

    func cleanupTemporaryFiles(urls: [URL])

    func saveTranscription(_ transcription: CaptureArtifact) async throws

    func saveModelPerformanceAttempt(_ attempt: ModelPerformanceAttempt) async throws

    func loadTranscriptions() async throws -> [CaptureArtifact]

    func loadAllMetadata() async throws -> [TranscriptionMetadata]

    func loadMetadata(matching query: TranscriptionMetadataQuery) async throws -> [TranscriptionMetadata]

    func loadModelPerformanceAttempts(matching query: ModelPerformanceAttemptQuery) async throws -> [ModelPerformanceAttempt]

    func loadTranscription(by id: UUID) async throws -> CaptureArtifact?

    func deleteTranscription(by id: UUID) async throws

    func cleanupOldTranscriptions(olderThanDays days: Int) async throws

    func computeRetentionCleanupPreview(olderThanDays days: Int) async throws -> RetentionCleanupPreview

    func performRetentionCleanup(preview: RetentionCleanupPreview) async throws -> RetentionCleanupResult
}

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

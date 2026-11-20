import Foundation
import VerbiCoreDomain
import VerbiCoreInfrastructure

public final class AudioFileRepositoryAdapter: AudioFileRepository {
    private let storageService: FileSystemStorageService

    public init(storageService: FileSystemStorageService) {
        self.storageService = storageService
    }

    public func saveAudioFile(from sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    public func deleteAudioFile(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    public func audioFileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func generateAudioFileURL(for meetingId: UUID) -> URL {
        let tempMeeting = CaptureSession(
            id: meetingId,
            app: .importedFile,
            startTime: Date()
        )
        return storageService.createRecordingURL(for: tempMeeting, type: .merged)
    }

    public func listAudioFiles() throws -> [URL] {
        let recordingsDir = storageService.recordingsDirectory
        let contents = try FileManager.default.contentsOfDirectory(
            at: recordingsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        return contents.filter { url in
            let ext = url.pathExtension.lowercased()
            return ["wav", "m4a", "mp3", "aac"].contains(ext)
        }
    }
}

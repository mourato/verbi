import Foundation

public final class ImportAudioUseCase {
    private let audioFileRepository: AudioFileRepository
    private let meetingRepository: MeetingRepository

    public init(
        audioFileRepository: AudioFileRepository,
        meetingRepository: MeetingRepository
    ) {
        self.audioFileRepository = audioFileRepository
        self.meetingRepository = meetingRepository
    }

    public func execute(
        sourceURL: URL,
        meetingTitle: String? = nil,
        capturePurpose: CapturePurpose = .dictation
    ) async throws -> (meeting: CaptureSessionEntity, audioFileURL: URL) {
        guard audioFileRepository.audioFileExists(at: sourceURL) else {
            throw ImportError.sourceFileNotFound
        }

        let meeting = CaptureSessionEntity(
            app: .importedFile,
            capturePurpose: capturePurpose,
            title: meetingTitle ?? sourceURL.deletingPathExtension().lastPathComponent,
            startTime: Date()
        )

        try await meetingRepository.saveMeeting(meeting)

        let destinationURL = audioFileRepository.generateAudioFileURL(for: meeting.id)

        do {
            try await audioFileRepository.saveAudioFile(from: sourceURL, to: destinationURL)
        } catch {
            try? await meetingRepository.deleteMeeting(by: meeting.id)
            throw ImportError.fileCopyFailed(error)
        }

        var updatedMeeting = meeting
        updatedMeeting.audioFilePath = destinationURL.path
        try await meetingRepository.updateMeeting(updatedMeeting)

        return (meeting: updatedMeeting, audioFileURL: destinationURL)
    }
}

public enum ImportError: Error {
    case sourceFileNotFound
    case invalidFileFormat
    case fileCopyFailed(Error)
    case meetingCreationFailed
}

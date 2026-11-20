import Foundation

public final class StartRecordingUseCase {
    private let recordingRepository: RecordingRepository
    private let audioFileRepository: AudioFileRepository
    private let meetingRepository: MeetingRepository

    public init(
        recordingRepository: RecordingRepository,
        audioFileRepository: AudioFileRepository,
        meetingRepository: MeetingRepository
    ) {
        self.recordingRepository = recordingRepository
        self.audioFileRepository = audioFileRepository
        self.meetingRepository = meetingRepository
    }

    public func execute(for meeting: CaptureSessionEntity) async throws -> URL {
        guard await recordingRepository.hasPermission() else {
            throw RecordingError.permissionDenied
        }

        let audioFileURL = audioFileRepository.generateAudioFileURL(for: meeting.id)

        do {
            try await recordingRepository.startRecording(to: audioFileURL, retryCount: 3)
        } catch {
            throw RecordingError.recordingFailed(error)
        }

        var updatedMeeting = meeting
        updatedMeeting.audioFilePath = audioFileURL.path
        try await meetingRepository.updateMeeting(updatedMeeting)

        return audioFileURL
    }
}

public enum RecordingError: Error {
    case permissionDenied
    case recordingFailed(Error)
    case invalidMeeting
    case fileCreationFailed
}

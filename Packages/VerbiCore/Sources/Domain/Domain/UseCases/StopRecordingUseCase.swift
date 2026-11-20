import Foundation

public final class StopRecordingUseCase {
    private let recordingRepository: RecordingRepository
    private let meetingRepository: MeetingRepository

    public init(
        recordingRepository: RecordingRepository,
        meetingRepository: MeetingRepository
    ) {
        self.recordingRepository = recordingRepository
        self.meetingRepository = meetingRepository
    }

    public func execute(for meeting: CaptureSessionEntity) async throws -> URL {
        guard let audioFileURL = try await recordingRepository.stopRecording() else {
            throw RecordingError.recordingFailed(NSError(domain: "StopRecordingUseCase", code: -1, userInfo: [NSLocalizedDescriptionKey: "No recording file URL returned"]))
        }

        var updatedMeeting = meeting
        updatedMeeting.endTime = Date()
        try await meetingRepository.updateMeeting(updatedMeeting)

        return audioFileURL
    }
}

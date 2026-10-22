import Foundation
@testable import VerbiCore
@testable import VerbiCoreDomain
import XCTest

final class StartRecordingUseCaseMacroMockingTests: XCTestCase {
    func testExecuteSuccess_UsesRepositoriesAndUpdatesMeeting() async throws {
        let recordingRepository = VerbiCoreDomain.MacroMockRecordingRepository()
        let audioFileRepository = VerbiCoreDomain.MacroMockAudioFileRepository()
        let meetingRepository = VerbiCoreDomain.MacroMockMeetingRepository()

        recordingRepository.hasPermissionHandler = { () async -> Bool in true }
        recordingRepository.startRecordingHandler = { _, _ in }

        let expectedURL = URL(fileURLWithPath: "/tmp/test.wav")
        audioFileRepository.generateAudioFileURLHandler = { _ in expectedURL }

        var updatedMeetings: [CaptureSessionEntity] = []
        meetingRepository.updateMeetingHandler = { meeting in
            updatedMeetings.append(meeting)
        }

        let useCase = StartRecordingUseCase(
            recordingRepository: recordingRepository,
            audioFileRepository: audioFileRepository,
            meetingRepository: meetingRepository,
        )

        let meeting = CaptureSessionEntity(app: .googleMeet)
        let result = try await useCase.execute(for: meeting)

        XCTAssertEqual(result, expectedURL)
        XCTAssertEqual(recordingRepository.hasPermissionCallCount, 1)
        XCTAssertEqual(recordingRepository.startRecordingCalls.count, 1)
        XCTAssertEqual(audioFileRepository.generateAudioFileURLCalls.count, 1)
        XCTAssertEqual(updatedMeetings.count, 1)
        XCTAssertEqual(updatedMeetings.first?.audioFilePath, expectedURL.path)
    }
}

import Foundation
@testable import VerbiCore
@testable import VerbiCoreDomain
import XCTest

final class StopRecordingUseCaseMacroMockingTests: XCTestCase {
    func testExecuteSuccess_StopsRecordingAndUpdatesMeeting() async throws {
        let recordingRepository = VerbiCoreDomain.MacroMockRecordingRepository()
        let meetingRepository = VerbiCoreDomain.MacroMockMeetingRepository()

        let expectedURL = URL(fileURLWithPath: "/tmp/test.wav")
        recordingRepository.stopRecordingHandler = { () async throws -> URL? in expectedURL }
        meetingRepository.updateMeetingHandler = { _ in }

        let useCase = StopRecordingUseCase(
            recordingRepository: recordingRepository,
            meetingRepository: meetingRepository,
        )

        let meeting = CaptureSessionEntity(app: .googleMeet)
        let result = try await useCase.execute(for: meeting)

        XCTAssertEqual(result, expectedURL)
        XCTAssertEqual(recordingRepository.stopRecordingCallCount, 1)
        XCTAssertEqual(meetingRepository.updateMeetingCalls.count, 1)
        XCTAssertNotNil(meetingRepository.updateMeetingCalls.first?.meeting.endTime)
    }
}

import Foundation
@testable import VerbiCore
@testable import VerbiCoreDomain
import XCTest

final class ImportAudioUseCaseMacroMockingTests: XCTestCase {
    func testExecuteSuccess_CopiesFileAndUpdatesMeeting() async throws {
        let audioFileRepository = VerbiCoreDomain.MacroMockAudioFileRepository()
        let meetingRepository = VerbiCoreDomain.MacroMockMeetingRepository()

        let sourceURL = URL(fileURLWithPath: "/tmp/source.wav")
        let destinationURL = URL(fileURLWithPath: "/tmp/dest.wav")

        audioFileRepository.audioFileExistsHandler = { _ in true }

        var savedMeetings: [CaptureSessionEntity] = []
        meetingRepository.saveMeetingHandler = { meeting in
            savedMeetings.append(meeting)
        }

        audioFileRepository.generateAudioFileURLHandler = { _ in destinationURL }
        audioFileRepository.saveAudioFileHandler = { _, _ in }

        var updatedMeetings: [CaptureSessionEntity] = []
        meetingRepository.updateMeetingHandler = { meeting in
            updatedMeetings.append(meeting)
        }

        let useCase = ImportAudioUseCase(
            audioFileRepository: audioFileRepository,
            meetingRepository: meetingRepository,
        )

        let result = try await useCase.execute(sourceURL: sourceURL)

        XCTAssertEqual(result.audioFileURL, destinationURL)
        XCTAssertEqual(result.meeting.audioFilePath, destinationURL.path)

        XCTAssertEqual(audioFileRepository.audioFileExistsCalls.count, 1)
        XCTAssertEqual(meetingRepository.saveMeetingCalls.count, 1)
        XCTAssertEqual(audioFileRepository.generateAudioFileURLCalls.count, 1)
        XCTAssertEqual(audioFileRepository.saveAudioFileCalls.count, 1)
        XCTAssertEqual(meetingRepository.updateMeetingCalls.count, 1)

        XCTAssertEqual(savedMeetings.count, 1)
        XCTAssertEqual(updatedMeetings.count, 1)
        XCTAssertEqual(updatedMeetings.first?.id, savedMeetings.first?.id)
        XCTAssertEqual(savedMeetings.first?.capturePurpose, .dictation)
    }

    func testExecute_AllowsExplicitMeetingPurpose() async throws {
        let audioFileRepository = VerbiCoreDomain.MacroMockAudioFileRepository()
        let meetingRepository = VerbiCoreDomain.MacroMockMeetingRepository()
        let sourceURL = URL(fileURLWithPath: "/tmp/source.wav")
        let destinationURL = URL(fileURLWithPath: "/tmp/dest.wav")

        audioFileRepository.audioFileExistsHandler = { _ in true }
        audioFileRepository.generateAudioFileURLHandler = { _ in destinationURL }
        audioFileRepository.saveAudioFileHandler = { _, _ in }

        var savedMeeting: CaptureSessionEntity?
        meetingRepository.saveMeetingHandler = { savedMeeting = $0 }
        meetingRepository.updateMeetingHandler = { _ in }

        let useCase = ImportAudioUseCase(
            audioFileRepository: audioFileRepository,
            meetingRepository: meetingRepository,
        )

        let result = try await useCase.execute(
            sourceURL: sourceURL,
            capturePurpose: .meeting,
        )

        XCTAssertEqual(result.meeting.capturePurpose, .meeting)
        XCTAssertEqual(savedMeeting?.capturePurpose, .meeting)
    }

    func testExecuteCopyFailure_DeletesMeeting() async {
        let audioFileRepository = VerbiCoreDomain.MacroMockAudioFileRepository()
        let meetingRepository = VerbiCoreDomain.MacroMockMeetingRepository()

        let sourceURL = URL(fileURLWithPath: "/tmp/source.wav")
        let destinationURL = URL(fileURLWithPath: "/tmp/dest.wav")

        audioFileRepository.audioFileExistsHandler = { _ in true }

        meetingRepository.saveMeetingHandler = { _ in }
        audioFileRepository.generateAudioFileURLHandler = { _ in destinationURL }

        struct CopyError: Error {}
        audioFileRepository.saveAudioFileHandler = { _, _ in throw CopyError() }

        meetingRepository.deleteMeetingHandler = { _ in }

        let useCase = ImportAudioUseCase(
            audioFileRepository: audioFileRepository,
            meetingRepository: meetingRepository,
        )

        do {
            _ = try await useCase.execute(sourceURL: sourceURL)
            XCTFail("Expected ImportError.fileCopyFailed")
        } catch ImportError.fileCopyFailed {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(meetingRepository.saveMeetingCalls.count, 1)
        XCTAssertEqual(meetingRepository.deleteMeetingCalls.count, 1)
    }
}

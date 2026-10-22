import VerbiCoreDomain
@testable import VerbiCoreUI
import XCTest

final class MenuBarRecordingSectionStateTests: XCTestCase {
    func testIdleWhenNoCaptureIsActive() {
        let state = MenuBarRecordingSectionState(
            isRecordingManagerActive: false,
            recordingSource: .microphone,
            isAssistantRecording: false,
        )

        XCTAssertEqual(state, .idle)
    }

    func testDictationWhenManagerIsActiveWithMicrophoneSource() {
        let state = MenuBarRecordingSectionState(
            isRecordingManagerActive: true,
            recordingSource: .microphone,
            isAssistantRecording: false,
        )

        XCTAssertEqual(state, .dictationActive)
    }

    func testMeetingWhenManagerIsActiveWithAllSource() {
        let state = MenuBarRecordingSectionState(
            isRecordingManagerActive: true,
            recordingSource: .all,
            isAssistantRecording: false,
        )

        XCTAssertEqual(state, .meetingActive)
    }

    func testAssistantWhenAssistantCaptureIsActive() {
        let state = MenuBarRecordingSectionState(
            isRecordingManagerActive: false,
            recordingSource: .microphone,
            isAssistantRecording: true,
        )

        XCTAssertEqual(state, .assistantActive)
    }

    func testManagerStartingStateIsRenderedAsActive() {
        let state = MenuBarRecordingSectionState(
            isRecordingManagerActive: true,
            recordingSource: .system,
            isAssistantRecording: false,
        )

        XCTAssertEqual(state, .meetingActive)
    }
}

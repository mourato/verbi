import VerbiCoreInfrastructure
@testable import VerbiCoreUI
import XCTest

final class AppCommandStateTests: XCTestCase {
    func testIdleStateShowsPrimaryCaptureActions() {
        let state = AppCommandState(recordingSection: .idle)

        XCTAssertTrue(state.showsDictationAction)
        XCTAssertTrue(state.showsMeetingAction)
        XCTAssertTrue(state.showsAssistantAction)
        XCTAssertFalse(state.showsCancelAction)
        XCTAssertEqual(state.dictationTitleKey, "menubar.dictate")
        XCTAssertEqual(state.meetingTitleKey, "menubar.record_meeting")
        XCTAssertEqual(state.assistantTitleKey, "menubar.assistant")
    }

    func testDictationStateShowsStopAndCancel() {
        let state = AppCommandState(recordingSection: .dictationActive)

        XCTAssertTrue(state.showsDictationAction)
        XCTAssertFalse(state.showsMeetingAction)
        XCTAssertFalse(state.showsAssistantAction)
        XCTAssertTrue(state.showsCancelAction)
        XCTAssertEqual(state.dictationTitleKey, "menubar.stop_dictation")
    }

    func testMeetingStateShowsStopAndCancel() {
        let state = AppCommandState(recordingSection: .meetingActive)

        XCTAssertFalse(state.showsDictationAction)
        XCTAssertTrue(state.showsMeetingAction)
        XCTAssertFalse(state.showsAssistantAction)
        XCTAssertTrue(state.showsCancelAction)
        XCTAssertEqual(state.meetingTitleKey, "menubar.stop_recording")
    }

    func testAssistantStateShowsStopAndCancel() {
        let state = AppCommandState(recordingSection: .assistantActive)

        XCTAssertFalse(state.showsDictationAction)
        XCTAssertFalse(state.showsMeetingAction)
        XCTAssertTrue(state.showsAssistantAction)
        XCTAssertTrue(state.showsCancelAction)
        XCTAssertEqual(state.assistantTitleKey, "menubar.stop_assistant")
    }

    func testAssistantActionIsHiddenWhenCapabilityDisabled() {
        let state = AppCommandState(
            recordingSection: .idle,
            assistantCapabilityEnabled: false,
        )

        XCTAssertFalse(state.showsAssistantAction)
    }

    func testCancelTitleKeyStaysStable() {
        let shortcut = ShortcutDefinition(
            modifiers: [.command],
            primaryKey: .letter("K", keyCode: 0x28),
            trigger: .singleTap,
        )
        let state = AppCommandState(
            recordingSection: .meetingActive,
            cancelRecordingShortcutDefinition: shortcut,
        )

        XCTAssertEqual(state.cancelTitleKey, "menubar.cancel_recording")
        XCTAssertEqual(state.cancelRecordingShortcutDefinition, shortcut)
    }
}

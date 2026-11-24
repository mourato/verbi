@testable import VerbiCoreAudio
import XCTest

@MainActor
final class MeetingRecorderTests: XCTestCase {
    func testInitialState() {
        let recorder = MeetingRecorder()

        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.currentRecordingURL)
        XCTAssertNil(recorder.error)
        XCTAssertEqual(recorder.currentAveragePower, -160.0)
        XCTAssertEqual(recorder.currentPeakPower, -160.0)
        XCTAssertEqual(recorder.defaultRecordingSource, .all)
    }

    func testStopRecordingWhenNotRecording() async {
        let recorder = MeetingRecorder()

        let result = await recorder.stopRecording()

        XCTAssertNil(result)
    }
}

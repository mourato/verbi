@testable import VerbiCore
@testable import VerbiCoreAudio
import XCTest

/// Testes unitários silenciosos para AudioRecorder.
@MainActor
final class AudioRecorderTests: XCTestCase {
    // Lazy initialization to avoid blocking in setUp
    private var _audioRecorder: AudioRecorder?
    var audioRecorder: AudioRecorder? {
        get {
            if _audioRecorder == nil {
                _audioRecorder = AudioRecorder()
            }
            return _audioRecorder
        }
        set { _audioRecorder = newValue }
    }

    override func tearDown() async throws {
        if let recorder = _audioRecorder {
            _ = await recorder.stopRecording()
        }
        _audioRecorder = nil
        try await super.tearDown()
    }

    // MARK: - Testes de Estado Inicial

    func testInitialState() {
        guard let audioRecorder else { return XCTFail("AudioRecorder not initialized") }
        XCTAssertFalse(audioRecorder.isRecording)
        XCTAssertNil(audioRecorder.currentRecordingURL)
        XCTAssertNil(audioRecorder.error)
        XCTAssertEqual(audioRecorder.currentAveragePower, -160.0)
        XCTAssertEqual(audioRecorder.currentPeakPower, -160.0)
    }

    // MARK: - Testes de Stop Recording

    func testStopRecordingWhenNotRecording() async {
        guard let audioRecorder else { return XCTFail("AudioRecorder not initialized") }
        let result = await audioRecorder.stopRecording()
        XCTAssertNil(result)
    }

}

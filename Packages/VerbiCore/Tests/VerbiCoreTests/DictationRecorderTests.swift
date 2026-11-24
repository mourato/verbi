@testable import VerbiCore
import Foundation
@testable import VerbiCoreAudio
import XCTest

@MainActor
final class DictationRecorderTests: XCTestCase {
    private var _audioRecorder: DictationRecorder?
    var audioRecorder: DictationRecorder? {
        get {
            if _audioRecorder == nil {
                _audioRecorder = DictationRecorder()
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

    func testInitialState() {
        guard let audioRecorder else { return XCTFail("DictationRecorder not initialized") }
        XCTAssertFalse(audioRecorder.isRecording)
        XCTAssertNil(audioRecorder.currentRecordingURL)
        XCTAssertNil(audioRecorder.error)
        XCTAssertEqual(audioRecorder.currentAveragePower, -160.0)
        XCTAssertEqual(audioRecorder.currentPeakPower, -160.0)
        XCTAssertEqual(audioRecorder.defaultRecordingSource, .microphone)
    }

    func testStopRecordingWhenNotRecording() async {
        guard let audioRecorder else { return XCTFail("DictationRecorder not initialized") }
        let result = await audioRecorder.stopRecording()
        XCTAssertNil(result)
    }

    func testSourceDoesNotReferenceMeetingOnlyComponents() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let directory = packageRoot.appendingPathComponent("Sources/Audio/Services/DictationRecorder")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        let source = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")

        for forbiddenReference in [
            "AVAudioEngine",
            "SystemAudioRecorder",
            "setSystemDefaultInputDevice",
            "DefaultInputDeviceWait"
        ] {
            XCTAssertFalse(source.contains(forbiddenReference), "DictationRecorder must not reference \(forbiddenReference)")
        }
    }
}

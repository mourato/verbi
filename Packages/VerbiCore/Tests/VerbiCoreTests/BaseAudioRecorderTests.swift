@testable import VerbiCoreAudio
import Foundation
import XCTest

@MainActor
final class BaseAudioRecorderTests: XCTestCase {
    func testCaptureStartHookThrowsRecoverableError() async {
        let recorder = BaseAudioRecorder()

        do {
            _ = try await recorder.performCaptureStart(
                to: URL(fileURLWithPath: "/tmp/base-recorder.m4a"),
                source: .microphone,
                retryCount: 0,
                generation: 0
            )
            XCTFail("Expected the base capture start hook to throw")
        } catch {
            guard case let .unsupportedRecordingSource(source) = error as? AudioRecorderError else {
                return XCTFail("Expected unsupportedRecordingSource, got \(error)")
            }
            XCTAssertEqual(source, .microphone)
        }
    }
}

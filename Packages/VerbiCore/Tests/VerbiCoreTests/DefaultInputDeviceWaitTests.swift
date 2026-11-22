import CoreAudio
@testable import VerbiCoreAudio
import XCTest

final class DefaultInputDeviceWaitTests: XCTestCase {
    func testWaitReturnsImmediatelyWhenDefaultAlreadyMatches() async throws {
        guard let current = AudioRecorder.currentDefaultInputDeviceID() else {
            throw XCTSkip("No system default input device available.")
        }
        let start = ContinuousClock().now
        try await AudioRecorder.waitForSystemDefaultInputDevice(current, timeout: .seconds(5))
        XCTAssertTrue(ContinuousClock().now - start < .seconds(1), "Matching default input must return without waiting.")
    }

    func testWaitContinuesAfterTimeoutWhenDeviceNeverMatches() async throws {
        let start = ContinuousClock().now
        try await AudioRecorder.waitForSystemDefaultInputDevice(
            AudioObjectID(kAudioObjectUnknown),
            timeout: .milliseconds(100)
        )
        XCTAssertTrue(ContinuousClock().now - start < .seconds(5), "Propagation wait must stay bounded.")
    }

    func testWaitThrowsOnCancellation() async {
        let task = Task {
            try await AudioRecorder.waitForSystemDefaultInputDevice(
                AudioObjectID(kAudioObjectUnknown),
                timeout: .seconds(30)
            )
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("Cancelled propagation wait must throw.")
        } catch is CancellationError {
        } catch {
            XCTFail("Cancelled propagation wait must throw CancellationError.")
        }
    }
}

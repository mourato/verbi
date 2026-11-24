import CoreAudio
@testable import VerbiCoreAudio
import XCTest

final class DefaultInputDeviceWaitTests: XCTestCase {
    func testWaitReturnsImmediatelyWhenDefaultAlreadyMatches() async throws {
        guard let current = AudioDeviceManager.defaultInputDeviceID() else {
            throw XCTSkip("No system default input device available.")
        }
        let start = ContinuousClock().now
        try await MeetingRecorder.waitForSystemDefaultInputDevice(current, timeout: .seconds(5))
        XCTAssertTrue(ContinuousClock().now - start < .seconds(1), "Matching default input must return without waiting.")
    }

    func testWaitContinuesAfterTimeoutWhenDeviceNeverMatches() async throws {
        let start = ContinuousClock().now
        try await MeetingRecorder.waitForSystemDefaultInputDevice(
            AudioObjectID(kAudioObjectUnknown),
            timeout: .milliseconds(100)
        )
        let elapsed = ContinuousClock().now - start
        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(100), "Wait must run until the timeout when the device never matches.")
        XCTAssertLessThan(elapsed, .seconds(5), "Propagation wait must stay bounded.")
    }

    func testWaitThrowsOnCancellation() async {
        let task = Task {
            try await MeetingRecorder.waitForSystemDefaultInputDevice(
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

    func testHolderCancelAbortsInFlightWait() async {
        let holder = DefaultInputDeviceWaitHolder()
        let started = expectation(description: "wait in flight")
        let task = Task {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let waiter = DefaultInputDeviceWait(
                    expectedID: AudioObjectID(kAudioObjectUnknown),
                    continuation: continuation
                )
                holder.store(waiter)
                waiter.start(timeout: .seconds(30))
                started.fulfill()
            }
        }
        await fulfillment(of: [started], timeout: 5)
        holder.cancel()
        let start = ContinuousClock().now
        do {
            try await task.value
            XCTFail("Holder cancellation must abort the wait.")
        } catch is CancellationError {
            XCTAssertLessThan(ContinuousClock().now - start, .seconds(5), "Cancelled wait must not run to its timeout.")
        } catch {
            XCTFail("Holder cancellation must throw CancellationError.")
        }
    }
}

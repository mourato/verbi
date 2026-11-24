@testable import VerbiCoreAudio
import XCTest

final class MeetingRecorderDeviceRecoveryTests: XCTestCase {
    func testShouldNotRecoverInputDevice_WhenEngineRunsThroughUnresolvedAggregate() {
        let devices = [
            AudioInputDevice(id: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone", isDefault: true)
        ]

        XCTAssertFalse(
            MeetingRecorder.shouldRecoverInputDevice(
                activeInputUID: "CADefaultDeviceAggregate-4242-0",
                desiredInputUID: "BuiltInMicrophoneDevice",
                availableDevices: devices
            )
        )
    }

    func testShouldRecoverInputDevice_WhenActiveDeviceDisappears() {
        let devices = [
            AudioInputDevice(id: "default-mic", name: "Default", isDefault: true)
        ]

        XCTAssertTrue(
            MeetingRecorder.shouldRecoverInputDevice(
                activeInputUID: "usb-mic",
                desiredInputUID: "default-mic",
                availableDevices: devices
            )
        )
    }

    func testShouldRecoverInputDevice_WhenPreferredDeviceBecomesAvailable() {
        let devices = [
            AudioInputDevice(id: "default-mic", name: "Default", isDefault: true),
            AudioInputDevice(id: "preferred-mic", name: "Preferred")
        ]

        XCTAssertTrue(
            MeetingRecorder.shouldRecoverInputDevice(
                activeInputUID: "default-mic",
                desiredInputUID: "preferred-mic",
                availableDevices: devices
            )
        )
    }

    func testShouldRecoverInputDevice_WhenDesiredAndActiveDevicesMatch() {
        let devices = [
            AudioInputDevice(id: "default-mic", name: "Default", isDefault: true),
            AudioInputDevice(id: "preferred-mic", name: "Preferred")
        ]

        XCTAssertFalse(
            MeetingRecorder.shouldRecoverInputDevice(
                activeInputUID: "preferred-mic",
                desiredInputUID: "preferred-mic",
                availableDevices: devices
            )
        )
    }

    func testShouldRecoverInputDevice_WhenDesiredDeviceIsUnavailable() {
        let devices = [
            AudioInputDevice(id: "default-mic", name: "Default", isDefault: true)
        ]

        XCTAssertFalse(
            MeetingRecorder.shouldRecoverInputDevice(
                activeInputUID: "default-mic",
                desiredInputUID: "preferred-mic",
                availableDevices: devices
            )
        )
    }
}

@testable import VerbiCoreAudio
import XCTest

final class AudioRecorderDeviceRecoveryTests: XCTestCase {
    func testShouldRecoverInputDevice_WhenActiveDeviceDisappears() {
        let devices = [
            AudioInputDevice(id: "default-mic", name: "Default", isDefault: true),
        ]

        XCTAssertTrue(
            AudioRecorder.shouldRecoverInputDevice(
                activeInputUID: "usb-mic",
                desiredInputUID: "default-mic",
                availableDevices: devices,
            ),
        )
    }

    func testShouldRecoverInputDevice_WhenPreferredDeviceBecomesAvailable() {
        let devices = [
            AudioInputDevice(id: "default-mic", name: "Default", isDefault: true),
            AudioInputDevice(id: "preferred-mic", name: "Preferred"),
        ]

        XCTAssertTrue(
            AudioRecorder.shouldRecoverInputDevice(
                activeInputUID: "default-mic",
                desiredInputUID: "preferred-mic",
                availableDevices: devices,
            ),
        )
    }

    func testShouldRecoverInputDevice_WhenDesiredAndActiveDevicesMatch() {
        let devices = [
            AudioInputDevice(id: "default-mic", name: "Default", isDefault: true),
            AudioInputDevice(id: "preferred-mic", name: "Preferred"),
        ]

        XCTAssertFalse(
            AudioRecorder.shouldRecoverInputDevice(
                activeInputUID: "preferred-mic",
                desiredInputUID: "preferred-mic",
                availableDevices: devices,
            ),
        )
    }

    func testShouldRecoverInputDevice_WhenDesiredDeviceIsUnavailable() {
        let devices = [
            AudioInputDevice(id: "default-mic", name: "Default", isDefault: true),
        ]

        XCTAssertFalse(
            AudioRecorder.shouldRecoverInputDevice(
                activeInputUID: "default-mic",
                desiredInputUID: "preferred-mic",
                availableDevices: devices,
            ),
        )
    }
}

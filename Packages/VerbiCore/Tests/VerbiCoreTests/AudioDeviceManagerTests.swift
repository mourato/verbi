import AVFoundation
@testable import VerbiCore
@testable import VerbiCoreAudio
import XCTest

@MainActor
final class AudioDeviceManagerTests: XCTestCase {
    var sut: AudioDeviceManager!

    override func setUp() async throws {
        try await super.setUp()
        sut = AudioDeviceManager()
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    func testIsDeviceAvailable() {
        let isAvailable = sut.isDeviceAvailable("some-random-id")
        XCTAssertFalse(isAvailable)
    }

    func testMonitoredPropertySelectors_IncludeDefaultInputAndHardwareDevices() {
        let selectors = AudioDeviceManager.monitoredPropertySelectorsForTesting()

        XCTAssertTrue(selectors.contains(kAudioHardwarePropertyDefaultInputDevice))
        XCTAssertTrue(selectors.contains(kAudioHardwarePropertyDevices))
    }

    func testIsIgnoredInput_ExcludesZoomVirtualDeviceButKeepsMicrophones() {
        XCTAssertTrue(AudioInputDevice.isIgnoredInput(uniqueID: "ZoomAudioDevice_UID", name: "ZoomAudioDevice"))
        XCTAssertFalse(AudioInputDevice.isIgnoredInput(uniqueID: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone"))
        XCTAssertTrue(AudioInputDevice.isIgnoredInput(uniqueID: "CADefaultDeviceAggregate-4242-0", name: "CADefaultDeviceAggregate-4242-0"))
    }
}

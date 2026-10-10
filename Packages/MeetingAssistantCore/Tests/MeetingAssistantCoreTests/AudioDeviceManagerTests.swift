import AVFoundation
@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreAudio
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

    func testInitialState() {
        // Just verify it can be initialized and doesn't crash
        XCTAssertNotNil(sut.availableInputDevices)
    }

    func testIsDeviceAvailable() {
        // This might be tricky in a test environment without real audio devices,
        // but we can at least check if it returns a boolean.
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
    }
}

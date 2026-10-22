import CoreAudio
@testable import VerbiCore
import XCTest

@MainActor
final class MicrophoneInputSelectionResolverTests: XCTestCase {
    private var settings: AppSettingsStore!

    override func setUp() async throws {
        settings = .shared
        settings.resetToDefaults()
    }

    override func tearDown() async throws {
        settings.resetToDefaults()
        settings = nil
    }

    func testResolveCustomMicrophoneDeviceID_UsesChargingSelectionOnACPower() {
        settings.useSystemDefaultInput = false
        settings.microphoneWhenChargingUID = "mic-ac"
        settings.microphoneOnBatteryUID = "mic-battery"

        let deviceResolver = MockMicrophoneDeviceResolver(
            deviceIDsByUID: ["mic-ac": 101, "mic-battery": 202],
            usableDeviceIDs: [101, 202],
            namesByDeviceID: [101: "Desk Mic", 202: "Laptop Mic"],
            defaultInputDeviceID: 999,
        )
        let resolver = MicrophoneInputSelectionResolver(
            deviceManager: deviceResolver,
            powerSourceProvider: MockPowerSourceStateProvider(state: .charging),
        )

        XCTAssertEqual(resolver.resolveCustomMicrophoneDeviceID(settings: settings), 101)
    }

    func testResolveCustomMicrophoneDeviceID_UsesBatterySelectionOnBatteryPower() {
        settings.useSystemDefaultInput = false
        settings.microphoneWhenChargingUID = "mic-ac"
        settings.microphoneOnBatteryUID = "mic-battery"

        let deviceResolver = MockMicrophoneDeviceResolver(
            deviceIDsByUID: ["mic-ac": 101, "mic-battery": 202],
            usableDeviceIDs: [101, 202],
            namesByDeviceID: [101: "Desk Mic", 202: "Laptop Mic"],
            defaultInputDeviceID: 999,
        )
        let resolver = MicrophoneInputSelectionResolver(
            deviceManager: deviceResolver,
            powerSourceProvider: MockPowerSourceStateProvider(state: .battery),
        )

        XCTAssertEqual(resolver.resolveCustomMicrophoneDeviceID(settings: settings), 202)
    }

    func testResolvePreferredMicrophoneDeviceName_FallsBackToSystemDefaultWhenCustomSelectionUnavailable() {
        settings.useSystemDefaultInput = false
        settings.microphoneWhenChargingUID = "missing-mic"
        settings.microphoneOnBatteryUID = "missing-mic"

        let deviceResolver = MockMicrophoneDeviceResolver(
            deviceIDsByUID: [:],
            usableDeviceIDs: [],
            namesByDeviceID: [909: "System Default Mic"],
            defaultInputDeviceID: 909,
        )
        let resolver = MicrophoneInputSelectionResolver(
            deviceManager: deviceResolver,
            powerSourceProvider: MockPowerSourceStateProvider(state: .charging),
        )

        XCTAssertEqual(
            resolver.resolvePreferredMicrophoneDeviceName(settings: settings),
            "System Default Mic",
        )
    }

    func testResolvePreferredMicrophoneDeviceName_UsesSystemDefaultWhenToggleIsEnabled() {
        settings.useSystemDefaultInput = true
        settings.microphoneWhenChargingUID = "mic-ac"
        settings.microphoneOnBatteryUID = "mic-battery"

        let deviceResolver = MockMicrophoneDeviceResolver(
            deviceIDsByUID: ["mic-ac": 101, "mic-battery": 202],
            usableDeviceIDs: [101, 202],
            namesByDeviceID: [101: "Desk Mic", 202: "Laptop Mic", 303: "System Default Mic"],
            defaultInputDeviceID: 303,
        )
        let resolver = MicrophoneInputSelectionResolver(
            deviceManager: deviceResolver,
            powerSourceProvider: MockPowerSourceStateProvider(state: .battery),
        )

        XCTAssertEqual(
            resolver.resolvePreferredMicrophoneDeviceName(settings: settings),
            "System Default Mic",
        )
    }
}

private struct MockPowerSourceStateProvider: PowerSourceStateProviding {
    let state: PowerSourceState

    func currentPowerSourceState() -> PowerSourceState {
        state
    }
}

@MainActor
private final class MockMicrophoneDeviceResolver: MicrophoneDeviceResolving {
    let availableInputDevices: [AudioInputDevice]
    private let deviceIDsByUID: [String: AudioObjectID]
    private let usableDeviceIDs: Set<AudioObjectID>
    private let namesByDeviceID: [AudioObjectID: String]
    private let defaultInputDeviceID: AudioObjectID?

    init(
        availableInputDevices: [AudioInputDevice] = [],
        deviceIDsByUID: [String: AudioObjectID],
        usableDeviceIDs: Set<AudioObjectID>,
        namesByDeviceID: [AudioObjectID: String],
        defaultInputDeviceID: AudioObjectID?,
    ) {
        self.availableInputDevices = availableInputDevices
        self.deviceIDsByUID = deviceIDsByUID
        self.usableDeviceIDs = usableDeviceIDs
        self.namesByDeviceID = namesByDeviceID
        self.defaultInputDeviceID = defaultInputDeviceID
    }

    func getAudioDeviceID(for uid: String) -> AudioObjectID? {
        deviceIDsByUID[uid]
    }

    func isUsableInputDeviceID(_ id: AudioObjectID) -> Bool {
        usableDeviceIDs.contains(id)
    }

    func getDeviceName(for id: AudioObjectID) -> String? {
        namesByDeviceID[id]
    }

    func getDefaultInputDeviceID() -> AudioObjectID? {
        defaultInputDeviceID
    }
}

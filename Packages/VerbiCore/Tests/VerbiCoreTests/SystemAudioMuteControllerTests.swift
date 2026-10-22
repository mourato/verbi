import AudioToolbox
@testable import VerbiCore
@testable import VerbiCoreAudio
import XCTest

final class SystemAudioMuteControllerTests: XCTestCase {
    var sut: SystemAudioMuteController!

    override func setUp() {
        super.setUp()
        sut = SystemAudioMuteController.shared
    }

    func testMuteToggle() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MA_ENABLE_AUDIO_HARDWARE_TESTS"] == "1",
            "Opt-in hardware test. Set MA_ENABLE_AUDIO_HARDWARE_TESTS=1 to run.",
        )

        let originalMuteState = sut.isMuted()
        var didToggle = false
        defer {
            if didToggle {
                do {
                    try sut.setMuted(originalMuteState)
                    XCTAssertEqual(sut.isMuted(), originalMuteState)
                } catch {
                    XCTFail("Failed to restore the original mute state: \(error)")
                }
            }
        }

        do {
            try sut.setMuted(!originalMuteState)
            didToggle = true
        } catch {
            throw XCTSkip("Audio mute is unavailable in this environment: \(error)")
        }

        XCTAssertEqual(sut.isMuted(), !originalMuteState)
    }

    func testMakeOutputVolumeStatePrefersVirtualMainVolume() {
        let channelState = SystemAudioMuteController.OutputScalarPropertyState(
            selector: kAudioDevicePropertyVolumeScalar,
            element: 1,
            value: 0.42,
        )

        let state = SystemAudioMuteController.makeOutputVolumeState(
            virtualMainVolume: 0.73,
            channelVolumes: [channelState],
        )

        XCTAssertEqual(
            state,
            SystemAudioMuteController.OutputVolumeState(
                properties: [
                    SystemAudioMuteController.OutputScalarPropertyState(
                        selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                        element: kAudioObjectPropertyElementMain,
                        value: 0.73,
                    ),
                ],
                strategyDescription: "virtualMainVolume",
            ),
        )
    }

    func testMakeOutputVolumeStateFallsBackToChannelVolumes() {
        let channelStates = [
            SystemAudioMuteController.OutputScalarPropertyState(
                selector: kAudioDevicePropertyVolumeScalar,
                element: 1,
                value: 0.30,
            ),
            SystemAudioMuteController.OutputScalarPropertyState(
                selector: kAudioDevicePropertyVolumeScalar,
                element: 2,
                value: 0.45,
            ),
        ]

        let state = SystemAudioMuteController.makeOutputVolumeState(
            virtualMainVolume: nil,
            channelVolumes: channelStates,
        )

        XCTAssertEqual(
            state,
            SystemAudioMuteController.OutputVolumeState(
                properties: channelStates,
                strategyDescription: "channelVolumeScalar",
            ),
        )
    }

    func testMakeOutputVolumeStateReturnsNilWithoutRestorableState() {
        XCTAssertNil(
            SystemAudioMuteController.makeOutputVolumeState(
                virtualMainVolume: nil,
                channelVolumes: [],
            ),
        )
    }

    func testMakeDuckedOutputVolumeStateScalesVolumeByPercent() {
        let state = SystemAudioMuteController.OutputVolumeState(
            properties: [
                SystemAudioMuteController.OutputScalarPropertyState(
                    selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                    element: kAudioObjectPropertyElementMain,
                    value: 0.8,
                ),
            ],
            strategyDescription: "virtualMainVolume",
        )

        let ducked = SystemAudioMuteController.makeDuckedOutputVolumeState(from: state, levelPercent: 30)

        XCTAssertEqual(ducked.properties.count, 1)
        XCTAssertEqual(ducked.properties[0].value, 0.24, accuracy: 0.0_001)
        XCTAssertEqual(ducked.strategyDescription, state.strategyDescription)
    }

    func testMakeDuckedOutputVolumeStateClampsPercentRange() {
        let state = SystemAudioMuteController.OutputVolumeState(
            properties: [
                SystemAudioMuteController.OutputScalarPropertyState(
                    selector: kAudioDevicePropertyVolumeScalar,
                    element: 1,
                    value: 0.65,
                ),
            ],
            strategyDescription: "channelVolumeScalar",
        )

        let muted = SystemAudioMuteController.makeDuckedOutputVolumeState(from: state, levelPercent: -10)
        let unchanged = SystemAudioMuteController.makeDuckedOutputVolumeState(from: state, levelPercent: 140)

        XCTAssertEqual(muted.properties[0].value, 0.0, accuracy: 0.0_001)
        XCTAssertEqual(unchanged.properties[0].value, 0.65, accuracy: 0.0_001)
    }
}

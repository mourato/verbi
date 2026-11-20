import AVFoundation
import os.lock
@testable import VerbiCore
@testable import VerbiCoreAudio
@testable import VerbiCoreInfrastructure
import XCTest

private final class RecordingSoundPlaybackEngineSpy: SoundFeedbackPlaybackEngine, @unchecked Sendable {
    struct SinglePlayCall: Equatable {
        let resourceName: String
        let volume: Float
    }

    struct PairedPreviewCall: Equatable {
        let startResourceName: String
        let stopResourceName: String
        let volume: Float
    }

    private struct State {
        var singlePlays: [SinglePlayCall] = []
        var pairedPreviews: [PairedPreviewCall] = []
        var cancelPreviewCount = 0
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    var singlePlays: [SinglePlayCall] {
        lock.withLock { $0.singlePlays }
    }

    var pairedPreviews: [PairedPreviewCall] {
        lock.withLock { $0.pairedPreviews }
    }

    var cancelPreviewCount: Int {
        lock.withLock { $0.cancelPreviewCount }
    }

    func play(resourceName: String, volume: Float) {
        lock.withLock { $0.singlePlays.append(SinglePlayCall(resourceName: resourceName, volume: volume)) }
    }

    func playPairedPreview(startResourceName: String, stopResourceName: String, volume: Float) {
        lock.withLock {
            $0.pairedPreviews.append(
                PairedPreviewCall(
                    startResourceName: startResourceName,
                    stopResourceName: stopResourceName,
                    volume: volume
                )
            )
        }
    }

    func cancelPendingPreview() {
        lock.withLock { $0.cancelPreviewCount += 1 }
    }
}

@MainActor
final class SoundFeedbackTests: XCTestCase {
    private var settings: AppSettingsStore!

    override func setUp() async throws {
        try AppSettingsTestIsolationLock.acquire()
        settings = .shared
        clearSoundFeedbackDefaults()
        settings.resetToDefaults()
    }

    override func tearDown() async throws {
        clearSoundFeedbackDefaults()
        settings?.resetToDefaults()
        settings = nil
        AppSettingsTestIsolationLock.release()
    }

    func testAllFourBundledCuePairsResolveAndLoadAsPlayableAudio() throws {
        XCTAssertEqual(SoundFeedbackCue.allCases, [.light, .creamy, .thocky, .petal])

        for cue in SoundFeedbackCue.allCases {
            for resourceName in [cue.startResourceName, cue.stopResourceName] {
                let url = try XCTUnwrap(
                    SoundFeedbackService.resourceURL(for: resourceName),
                    "Expected bundled sound resource \(resourceName).m4a to exist"
                )
                let player = try AVAudioPlayer(contentsOf: url)
                XCTAssertGreaterThan(
                    player.duration,
                    0,
                    "Expected bundled sound \(resourceName).m4a to have positive duration"
                )
            }
        }
    }

    func testSoundFeedbackSettingsPersistAndClampVolumeThroughViewModelReload() {
        let firstViewModel = GeneralSettingsViewModel(
            settingsStore: settings,
            deviceManager: GeneralSettingsAudioDeviceTestDouble()
        )
        firstViewModel.soundFeedbackEnabled = true
        firstViewModel.soundFeedbackCue = .thocky
        firstViewModel.soundFeedbackVolume = 1.4

        XCTAssertEqual(settings.soundFeedbackCue, .thocky)
        XCTAssertEqual(settings.soundFeedbackVolume, 1.0, accuracy: 0.0001)
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppSettingsStore.Keys.soundFeedbackCue), "thocky")

        firstViewModel.soundFeedbackVolume = 0.65
        let reloadedViewModel = GeneralSettingsViewModel(
            settingsStore: settings,
            deviceManager: GeneralSettingsAudioDeviceTestDouble()
        )

        XCTAssertTrue(reloadedViewModel.soundFeedbackEnabled)
        XCTAssertEqual(reloadedViewModel.soundFeedbackCue, .thocky)
        XCTAssertEqual(reloadedViewModel.soundFeedbackVolume, 0.65, accuracy: 0.0001)

        settings.resetToDefaults()
        XCTAssertEqual(settings.soundFeedbackCue, .light)
        XCTAssertEqual(settings.soundFeedbackVolume, 1.0, accuracy: 0.0001)
    }

    func testServiceRespectsEnabledToggleAndConfiguredCueAndVolume() {
        let spy = RecordingSoundPlaybackEngineSpy()
        var cancelledCalls: [(SoundFeedbackSound, Float)] = []
        let service = SoundFeedbackService(
            settings: settings,
            playbackEngine: spy,
            systemSoundHandler: { sound, volume in
                cancelledCalls.append((sound, volume))
            }
        )

        settings.soundFeedbackEnabled = false
        settings.soundFeedbackCue = .creamy
        settings.soundFeedbackVolume = 0.5

        service.playRecordingStartSound()
        service.playRecordingStopSound()
        service.playRecordingCancelledSound()

        XCTAssertTrue(spy.singlePlays.isEmpty)
        XCTAssertTrue(cancelledCalls.isEmpty)
        XCTAssertEqual(spy.cancelPreviewCount, 3)

        settings.soundFeedbackEnabled = true
        service.playRecordingStartSound()
        service.playRecordingStopSound()
        service.playRecordingCancelledSound()

        XCTAssertEqual(
            spy.singlePlays,
            [
                .init(resourceName: "creamy_start", volume: 0.5),
                .init(resourceName: "creamy_stop", volume: 0.5)
            ]
        )
        XCTAssertEqual(cancelledCalls.count, 1)
        XCTAssertEqual(cancelledCalls.first?.0, .basso)
        XCTAssertEqual(cancelledCalls.first?.1 ?? -1, 0.5, accuracy: 0.0001)
    }

    func testPreviewPlaysPairedCueAndVolumePreviewClampsInput() {
        let spy = RecordingSoundPlaybackEngineSpy()
        let service = SoundFeedbackService(
            settings: settings,
            playbackEngine: spy,
            systemSoundHandler: { _, _ in }
        )

        settings.soundFeedbackEnabled = false
        settings.soundFeedbackCue = .petal
        settings.soundFeedbackVolume = 0.75

        service.preview(.petal)
        service.previewAtVolume(-0.25)

        XCTAssertEqual(
            spy.pairedPreviews,
            [.init(startResourceName: "petal_start", stopResourceName: "petal_stop", volume: 0.75)]
        )
        XCTAssertEqual(
            spy.singlePlays,
            [.init(resourceName: "petal_start", volume: 0.0)]
        )
    }

    func testLegacyBothNoneSoundsDisableFeedbackOnceAndPreserveReenable() {
        clearSoundFeedbackDefaults()
        UserDefaults.standard.set(true, forKey: AppSettingsStore.Keys.soundFeedbackEnabled)
        UserDefaults.standard.set(SoundFeedbackSound.none.rawValue, forKey: AppSettingsStore.Keys.recordingStartSound)
        UserDefaults.standard.set(SoundFeedbackSound.none.rawValue, forKey: AppSettingsStore.Keys.recordingStopSound)

        let firstLoad = AppSettingsStore.loadUIAndIndicatorSettings()
        XCTAssertFalse(firstLoad.soundFeedbackEnabled)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: AppSettingsStore.Keys.soundFeedbackEnabled))
        XCTAssertEqual(firstLoad.soundFeedbackCue, .light)
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppSettingsStore.Keys.soundFeedbackCue), SoundFeedbackCue.light.rawValue)

        // Explicitly re-enabling sound feedback without changing the cue picker must stick on relaunch.
        UserDefaults.standard.set(true, forKey: AppSettingsStore.Keys.soundFeedbackEnabled)
        let secondLoad = AppSettingsStore.loadUIAndIndicatorSettings()
        XCTAssertTrue(secondLoad.soundFeedbackEnabled)
        XCTAssertEqual(secondLoad.soundFeedbackCue, .light)
    }

    func testLegacySystemSoundsMigrateToMatchingBundledCue() {
        clearSoundFeedbackDefaults()
        UserDefaults.standard.set(true, forKey: AppSettingsStore.Keys.soundFeedbackEnabled)
        UserDefaults.standard.set(SoundFeedbackSound.purr.rawValue, forKey: AppSettingsStore.Keys.recordingStartSound)
        UserDefaults.standard.set(SoundFeedbackSound.glass.rawValue, forKey: AppSettingsStore.Keys.recordingStopSound)

        let warmLoad = AppSettingsStore.loadUIAndIndicatorSettings()
        XCTAssertTrue(warmLoad.soundFeedbackEnabled)
        XCTAssertEqual(warmLoad.soundFeedbackCue, .creamy)
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppSettingsStore.Keys.soundFeedbackCue), SoundFeedbackCue.creamy.rawValue)

        // One-sided legacy `.none` on start falls back to mapping the stop sound.
        clearSoundFeedbackDefaults()
        UserDefaults.standard.set(true, forKey: AppSettingsStore.Keys.soundFeedbackEnabled)
        UserDefaults.standard.set(SoundFeedbackSound.none.rawValue, forKey: AppSettingsStore.Keys.recordingStartSound)
        UserDefaults.standard.set(SoundFeedbackSound.bottle.rawValue, forKey: AppSettingsStore.Keys.recordingStopSound)

        let oneSidedLoad = AppSettingsStore.loadUIAndIndicatorSettings()
        XCTAssertTrue(oneSidedLoad.soundFeedbackEnabled)
        XCTAssertEqual(oneSidedLoad.soundFeedbackCue, .thocky)
    }

    private func clearSoundFeedbackDefaults() {
        [
            AppSettingsStore.Keys.soundFeedbackEnabled,
            AppSettingsStore.Keys.soundFeedbackCue,
            AppSettingsStore.Keys.soundFeedbackVolume,
            AppSettingsStore.Keys.recordingStartSound,
            AppSettingsStore.Keys.recordingStopSound
        ].forEach(UserDefaults.standard.removeObject)
    }
}

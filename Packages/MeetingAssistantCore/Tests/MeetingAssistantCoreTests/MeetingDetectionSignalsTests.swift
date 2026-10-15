import AppKit
import CoreAudio
import Foundation
@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreCommon
@testable import MeetingAssistantCoreDomain
@testable import MeetingAssistantCoreInfrastructure
@testable import MeetingAssistantCoreUI
import os
import XCTest

@MainActor
final class MeetingDetectionSignalsTests: XCTestCase {
    func testProductionProcessProviderResolvesRunningInputOwner() {
        let hal = FakeCoreAudioHAL()
        hal.setProcessIDs([101])
        let processProvider = CoreAudioMeetingProcessProvider(startListening: false, hal: hal)
        let activity = SystemMeetingMediaActivityProvider(audioProcessProvider: processProvider).currentActivity()

        XCTAssertTrue(activity.isActive)
        XCTAssertEqual(activity.signals.attribution, .resolved)
        XCTAssertEqual(activity.signals.microphoneOwnerBundleIdentifier, "us.zoom.xos")
    }

    func testOwnerResolvedAttribution() {
        let fakeAudioProvider = FakeMeetingAudioProcessProvider()
        fakeAudioProvider.runningProcesses = [
            AudioProcessInfo(
                processID: 101,
                pid: 1234,
                bundleIdentifier: "us.zoom.xos",
                displayName: "zoom.us",
                isRunningInput: true
            )
        ]

        let mediaProvider = SystemMeetingMediaActivityProvider(audioProcessProvider: fakeAudioProvider)
        let activity = mediaProvider.currentActivity()

        XCTAssertEqual(activity.signals.attribution, .resolved)
        XCTAssertEqual(activity.signals.microphoneOwnerBundleIdentifier, "us.zoom.xos")
        XCTAssertEqual(activity.signals.microphoneOwnerDisplayName, "zoom.us")
        XCTAssertEqual(activity.signals.activeCallBundleIdentifiers, ["us.zoom.xos"])
        XCTAssertTrue(activity.signals.isResolved)
        XCTAssertFalse(activity.signals.isUnattributed)
        XCTAssertFalse(activity.signals.isUnavailable)
    }

    func testDegradedModeUnattributedWhenMicInUseWithoutOwner() throws {
        try AppSettingsTestIsolationLock.acquire()
        defer { AppSettingsTestIsolationLock.release() }
        let hal = FakeCoreAudioHAL(bundleIdentifier: nil)
        hal.setProcessIDs([101])
        let processProvider = CoreAudioMeetingProcessProvider(startListening: false, hal: hal)
        let mediaProvider = SystemMeetingMediaActivityProvider(audioProcessProvider: processProvider)
        let activity = mediaProvider.currentActivity()

        XCTAssertTrue(activity.isActive)
        XCTAssertEqual(activity.signals.attribution, .unattributed)
        XCTAssertNil(activity.signals.microphoneOwnerBundleIdentifier)

        let settings = AppSettingsStore.shared
        let previousTargets = settings.monitoredMeetingBundleIdentifiers
        defer { settings.monitoredMeetingBundleIdentifiers = previousTargets }
        let runningApp = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first)
        let bundleID = try XCTUnwrap(runningApp.bundleIdentifier)
        settings.monitoredMeetingBundleIdentifiers = [bundleID]
        let resolver = CaptureContextResolver(settings: settings, mediaActivityProvider: mediaProvider)
        let candidate = resolver.detectMeetingCandidate(in: [runningApp])
        XCTAssertEqual(candidate?.appBundleIdentifier, bundleID)
        XCTAssertEqual(candidate?.isKnownMeetingCandidate, true)
    }

    func testUnavailableWhenNoMicInUseAndNoProcesses() {
        let fakeAudioProvider = FakeMeetingAudioProcessProvider()
        fakeAudioProvider.runningProcesses = []

        let mediaProvider = SystemMeetingMediaActivityProvider(audioProcessProvider: fakeAudioProvider)
        let activity = mediaProvider.currentActivity()

        XCTAssertEqual(activity.signals.attribution, .unavailable)
        XCTAssertNil(activity.signals.microphoneOwnerBundleIdentifier)
        XCTAssertTrue(activity.signals.isUnavailable)
        XCTAssertFalse(activity.signals.isResolved)
        XCTAssertFalse(activity.signals.isUnattributed)
    }

    func testMultipleProcessesSelectsKnownMeetingAppAsOwner() {
        let fakeAudioProvider = FakeMeetingAudioProcessProvider()
        fakeAudioProvider.runningProcesses = [
            AudioProcessInfo(
                processID: 201,
                pid: 5678,
                bundleIdentifier: "com.example.recorder",
                displayName: "Recorder",
                isRunningInput: true
            ),
            AudioProcessInfo(
                processID: 202,
                pid: 5679,
                bundleIdentifier: "us.zoom.xos",
                displayName: "zoom.us",
                isRunningInput: true
            )
        ]

        let mediaProvider = SystemMeetingMediaActivityProvider(audioProcessProvider: fakeAudioProvider)
        let activity = mediaProvider.currentActivity()

        XCTAssertEqual(activity.signals.attribution, .resolved)
        XCTAssertEqual(activity.signals.microphoneOwnerBundleIdentifier, "us.zoom.xos")
        XCTAssertEqual(activity.signals.activeCallBundleIdentifiers, ["com.example.recorder", "us.zoom.xos"])
    }

    func testOwnerChangeDebouncePreventsDoubleFire() async {
        let fakeHAL = FakeCoreAudioHAL()
        fakeHAL.setProcessIDs([100])

        // Exercise PRODUCTION CoreAudioMeetingProcessProvider at the lowest CoreAudio HAL seam
        let provider = CoreAudioMeetingProcessProvider(
            debounceInterval: 0.05,
            startListening: true,
            hal: fakeHAL
        )

        let fireCounter = OSAllocatedUnfairLock(initialState: 0)
        provider.onProcessActivityChanged = {
            fireCounter.withLock { $0 += 1 }
        }

        // Fire 2 rapid events through the HAL seam
        fakeHAL.fireListeners()
        fakeHAL.fireListeners()

        await waitUntil(timeout: .milliseconds(500)) {
            fireCounter.withLock { $0 == 1 }
        }

        let finalCount = fireCounter.withLock { $0 }
        XCTAssertEqual(finalCount, 1, "Debounced callback should fire only once for rapid events")
    }

    func testMeetingDetectorObservesAudioProcessChanges() async {
        let fakeAudioProvider = FakeMeetingAudioProcessProvider(debounceInterval: 0.01)
        let testSignals = MeetingDetectionSignals(
            microphoneOwnerBundleIdentifier: "us.zoom.xos",
            microphoneOwnerDisplayName: "zoom.us",
            attribution: .resolved,
            activeCallBundleIdentifiers: ["us.zoom.xos"]
        )
        let fakeMediaProvider = FakeMediaActivityProvider()
        fakeMediaProvider.activity = MeetingMediaActivity(
            microphoneInUseByAnotherApplication: true,
            cameraInUseByAnotherApplication: false,
            signals: testSignals
        )

        let detector = MeetingDetector(
            mediaActivityProvider: fakeMediaProvider,
            audioProcessProvider: fakeAudioProvider
        )

        detector.startMonitoring()
        defer { detector.stopMonitoring() }

        XCTAssertEqual(detector.detectionSignals?.microphoneOwnerBundleIdentifier, "us.zoom.xos")
        XCTAssertEqual(detector.detectionSignals?.attribution, .resolved)

        // Now change activity
        let updatedSignals = MeetingDetectionSignals(
            microphoneOwnerBundleIdentifier: nil,
            attribution: .unavailable,
            activeCallBundleIdentifiers: []
        )
        fakeMediaProvider.activity = MeetingMediaActivity(
            microphoneInUseByAnotherApplication: false,
            signals: updatedSignals
        )

        fakeAudioProvider.triggerChangeImmediately()

        await waitUntil(timeout: .milliseconds(500)) {
            detector.detectionSignals?.attribution == .unavailable
        }

        XCTAssertEqual(detector.detectionSignals?.attribution, .unavailable)
    }

    func testMeetingMediaActivityIsActiveSemanticsUnchanged() {
        let micOnly = MeetingMediaActivity(
            microphoneInUseByAnotherApplication: true,
            cameraInUseByAnotherApplication: false
        )
        XCTAssertTrue(micOnly.isActive)

        let cameraOnly = MeetingMediaActivity(
            microphoneInUseByAnotherApplication: false,
            cameraInUseByAnotherApplication: true
        )
        XCTAssertTrue(cameraOnly.isActive)

        let both = MeetingMediaActivity(
            microphoneInUseByAnotherApplication: true,
            cameraInUseByAnotherApplication: true
        )
        XCTAssertTrue(both.isActive)

        let neither = MeetingMediaActivity(
            microphoneInUseByAnotherApplication: false,
            cameraInUseByAnotherApplication: false
        )
        XCTAssertFalse(neither.isActive)
    }
}

// MARK: - Test Doubles

private final class FakeCoreAudioHAL: CoreAudioHALProtocol, @unchecked Sendable // justified: test fake state protected by NSLock
{
    private let lock = NSLock()
    private let bundleIdentifier: String?

    init(bundleIdentifier: String? = "us.zoom.xos") {
        self.bundleIdentifier = bundleIdentifier
    }

    private var _processIDs: [AudioObjectID] = []
    private var _systemListeners: [AudioObjectPropertyListenerBlock] = []
    private var _processListeners: [AudioObjectID: [AudioObjectPropertyListenerBlock]] = [:]
    private var _allProcessListeners: [AudioObjectPropertyListenerBlock] = []

    func setProcessIDs(_ ids: [AudioObjectID]) {
        lock.withLock { _processIDs = ids }
    }

    func fetchProcessIDs() -> [AudioObjectID] {
        lock.withLock { _processIDs }
    }

    func isProcessRunningInput(_: AudioObjectID) -> Bool {
        true
    }

    func fetchBundleIdentifier(for _: AudioObjectID) -> String? {
        bundleIdentifier
    }

    func fetchPID(for _: AudioObjectID) -> pid_t {
        1234
    }

    func addSystemListener(_ listener: @escaping AudioObjectPropertyListenerBlock) -> OSStatus {
        lock.withLock { _systemListeners.append(listener) }
        return noErr
    }

    func removeSystemListener(_: @escaping AudioObjectPropertyListenerBlock) {}

    func addProcessListener(processID: AudioObjectID, _ listener: @escaping AudioObjectPropertyListenerBlock) -> OSStatus {
        lock.withLock {
            _processListeners[processID, default: []].append(listener)
            _allProcessListeners.append(listener)
        }
        return noErr
    }

    func removeProcessListener(processID _: AudioObjectID, _: @escaping AudioObjectPropertyListenerBlock) {}

    func fireListeners() {
        let listeners = lock.withLock { _allProcessListeners }
        var address = AudioObjectPropertyAddress()
        for listener in listeners {
            listener(1, &address)
        }
    }
}

private final class FakeMeetingAudioProcessProvider: MeetingAudioProcessProviding, @unchecked Sendable // justified: test fake mutable state protected by NSLock
{
    private let lock = NSLock()
    private var _runningProcesses: [AudioProcessInfo] = []
    private var _onProcessActivityChanged: (@Sendable () -> Void)?
    let debounceInterval: TimeInterval

    init(debounceInterval: TimeInterval = 0.05) {
        self.debounceInterval = debounceInterval
    }

    var runningProcesses: [AudioProcessInfo] {
        get {
            lock.withLock { _runningProcesses }
        }
        set {
            lock.withLock { _runningProcesses = newValue }
        }
    }

    var onProcessActivityChanged: (@Sendable () -> Void)? {
        get {
            lock.withLock { _onProcessActivityChanged }
        }
        set {
            lock.withLock { _onProcessActivityChanged = newValue }
        }
    }

    func runningInputProcesses() -> [AudioProcessInfo] {
        lock.withLock { _runningProcesses }
    }

    func triggerChangeImmediately() {
        let callback = lock.withLock { _onProcessActivityChanged }
        callback?()
    }
}

private final class FakeMediaActivityProvider: MeetingMediaActivityProviding, @unchecked Sendable // justified: test fake mutable state protected by NSLock
{
    private let lock = NSLock()
    private var _activity = MeetingMediaActivity()

    var activity: MeetingMediaActivity {
        get {
            lock.withLock { _activity }
        }
        set {
            lock.withLock { _activity = newValue }
        }
    }

    func currentActivity() -> MeetingMediaActivity {
        lock.withLock { _activity }
    }
}

import AppKit
import Foundation
@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreCommon
@testable import MeetingAssistantCoreDomain
@testable import MeetingAssistantCoreInfrastructure
import os
import XCTest

@MainActor
final class MeetingDetectionSignalsTests: XCTestCase {
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

    func testDegradedModeUnattributedWhenMicInUseWithoutOwner() {
        // Degraded mode: AVCaptureDevice reports mic in use, but CoreAudio cannot resolve owner
        let fakeAudioProvider = FakeMeetingAudioProcessProvider()
        fakeAudioProvider.runningProcesses = []

        // Create a media activity representing degraded mode directly
        let signals = MeetingDetectionSignals(
            microphoneOwnerBundleIdentifier: nil,
            microphoneOwnerDisplayName: nil,
            attribution: .unattributed,
            activeCallBundleIdentifiers: []
        )
        let activity = MeetingMediaActivity(
            microphoneInUseByAnotherApplication: true,
            cameraInUseByAnotherApplication: false,
            signals: signals
        )

        XCTAssertTrue(activity.isActive)
        XCTAssertEqual(activity.signals.attribution, .unattributed)
        XCTAssertNil(activity.signals.microphoneOwnerBundleIdentifier)
        XCTAssertTrue(activity.signals.isUnattributed)
        XCTAssertFalse(activity.signals.isResolved)
        XCTAssertFalse(activity.signals.isUnavailable)
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
        let fakeAudioProvider = FakeMeetingAudioProcessProvider(debounceInterval: 0.05)
        let fireCounter = OSAllocatedUnfairLock(initialState: 0)

        fakeAudioProvider.onProcessActivityChanged = {
            fireCounter.withLock { $0 += 1 }
        }

        // Simulate rapid changes (handoff between apps A and B)
        fakeAudioProvider.triggerChangeWithDebounce()
        fakeAudioProvider.triggerChangeWithDebounce()

        await waitUntil(timeout: .milliseconds(500)) {
            fireCounter.withLock { $0 == 1 }
        }

        let finalCount = fireCounter.withLock { $0 }
        XCTAssertEqual(finalCount, 1, "Debounced callback should fire only once for rapid handoff")
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

private final class FakeMeetingAudioProcessProvider: MeetingAudioProcessProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _runningProcesses: [AudioProcessInfo] = []
    private var _onProcessActivityChanged: (@Sendable () -> Void)?
    private var _debounceTask: Task<Void, Never>?
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

    func triggerChangeWithDebounce() {
        lock.lock()
        _debounceTask?.cancel()
        let interval = debounceInterval
        _debounceTask = Task { [weak self] in
            // test-hygiene: allow sleep debounce timer implementation inside test fake
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            let callback = self?.lock.withLock { self?._onProcessActivityChanged }
            callback?()
        }
        lock.unlock()
    }

    func triggerChangeImmediately() {
        let callback = lock.withLock { _onProcessActivityChanged }
        callback?()
    }
}

private final class FakeMediaActivityProvider: MeetingMediaActivityProviding, @unchecked Sendable {
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

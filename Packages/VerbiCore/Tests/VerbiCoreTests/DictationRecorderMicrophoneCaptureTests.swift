import AVFoundation
@testable import VerbiCore
@testable import VerbiCoreAudio
@testable import VerbiCoreInfrastructure
import XCTest

@MainActor
final class DictationRecorderMicrophoneCaptureTests: XCTestCase {
    private var recorder: DictationRecorder?
    private var ownedURLs: [URL] = []

    override func tearDown() async throws {
        if let recorder {
            _ = await recorder.stopRecording()
        }
        recorder = nil
        for url in ownedURLs {
            try? FileManager.default.removeItem(at: url)
        }
        ownedURLs = []
        try await super.tearDown()
    }

    func testMicrophoneCaptureStartDeliversBuffersAndStopReturnsFile() async throws {
        let fake = try FakeMicrophoneCaptureSession()
        let recorder = makeRecorder(capture: fake)
        let url = makeTemporaryURL()
        recorder.activeRecordingSource = .microphone

        try await recorder.startMicrophoneCaptureRecording(to: url, retryCount: 0)

        XCTAssertTrue(recorder.isRecording)
        XCTAssertEqual(recorder.currentRecordingURL, url)
        XCTAssertEqual(fake.recordedDeviceUIDs.count, 1)

        fake.emitValidBuffer()
        await waitForValidBuffer(recorder)

        let stoppedURL = await recorder.stopRecording()

        XCTAssertEqual(stoppedURL, url)
        let writtenFile = try AVAudioFile(forReading: url)
        XCTAssertGreaterThan(writtenFile.length, 0)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(fake.stopCallCount, 1)
    }

    func testMicrophoneCaptureValidationWithoutAudioReportsFailure() async throws {
        let fake = try FakeMicrophoneCaptureSession()
        let recorder = makeRecorder(capture: fake)
        recorder.validationInterval = 3600
        recorder.activeRecordingSource = .microphone
        let reported = CapturedRecordingError()
        recorder.onRecordingError = { reported.set($0) }
        let url = makeTemporaryURL()

        try await recorder.startMicrophoneCaptureRecording(to: url, retryCount: 0)
        let sessionID = try XCTUnwrap(recorder.activeValidationSessionID)

        await recorder.handleValidationTimeout(
            url: url,
            source: .microphone,
            retryCount: 0,
            sessionID: sessionID,
            allowsRestart: false
        )

        guard case .recordingValidationFailed? = reported.value as? AudioRecorderError else {
            return XCTFail("Expected recordingValidationFailed, got \(String(describing: reported.value))")
        }
    }

    func testMicrophoneCaptureFailureMidRecordingReportsInterruption() async throws {
        let fake = try FakeMicrophoneCaptureSession()
        let recorder = makeRecorder(capture: fake)
        recorder.activeRecordingSource = .microphone
        let reported = CapturedRecordingError()
        recorder.onRecordingError = { reported.set($0) }
        let url = makeTemporaryURL()

        try await recorder.startMicrophoneCaptureRecording(to: url, retryCount: 0)
        fake.emitValidBuffer()
        await waitForValidBuffer(recorder)
        fake.fail(FakeMicrophoneCaptureSessionError.simulatedFailure)

        await waitUntil(timeout: .seconds(5), message: "Capture failure should be reported.") {
            reported.value != nil
        }

        guard case .microphoneCaptureInterrupted? = reported.value as? AudioRecorderError else {
            return XCTFail("Expected microphoneCaptureInterrupted, got \(String(describing: reported.value))")
        }
        XCTAssertTrue(recorder.isRecording)
        XCTAssertNotNil(recorder.error)
    }

    func testStartRecordingMicrophoneWithoutForwarderUsesCaptureSession() async throws {
        let fake = try FakeMicrophoneCaptureSession()
        let recorder = makeRecorder(capture: fake)
        recorder.microphonePermissionValidator = {}
        recorder.onMixedAudioBuffer = nil
        let url = makeTemporaryURL()

        try await recorder.startRecording(to: url, source: .microphone)

        XCTAssertEqual(fake.recordedDeviceUIDs.count, 1)
        XCTAssertTrue(recorder.isRecording)
        XCTAssertEqual(recorder.currentRecordingURL, url)
        XCTAssertEqual(recorder.activeRecordingSource, .microphone)

        fake.emitValidBuffer()
        await waitForValidBuffer(recorder)

        let stoppedURL = await recorder.stopRecording()
        XCTAssertEqual(stoppedURL, url)
        let writtenFile = try AVAudioFile(forReading: url)
        XCTAssertGreaterThan(writtenFile.length, 0)
    }

    func testStartRecordingMicrophoneWithForwarderStillUsesCaptureSession() async throws {
        let fake = try FakeMicrophoneCaptureSession()
        let recorder = makeRecorder(capture: fake)
        recorder.microphonePermissionValidator = {}
        let forwarded = LockedCounter()
        recorder.onMixedAudioBuffer = { _ in forwarded.increment() }
        let url = makeTemporaryURL()

        try await recorder.startRecording(to: url, source: .microphone)

        XCTAssertEqual(fake.recordedDeviceUIDs.count, 1)

        fake.emitValidBuffer()
        await waitForValidBuffer(recorder)
        await waitUntil(timeout: .seconds(5), message: "Forwarder should receive the captured buffer.") {
            !forwarded.isEmpty
        }

        _ = await recorder.stopRecording()
    }

    func testQuestionDictationRecordingUsesCaptureSession() async throws {
        let fake = try FakeMicrophoneCaptureSession()
        let recorder = makeRecorder(capture: fake)
        recorder.microphonePermissionValidator = {}
        let url = makeTemporaryURL()

        try await startQuestionDictation(on: recorder, to: url)

        XCTAssertEqual(fake.recordedDeviceUIDs.count, 1)
        XCTAssertTrue(recorder.isRecording)

        _ = await recorder.stopRecording()
    }

    private func startQuestionDictation(
        on recorder: some MeetingQuestionDictationRecording,
        to url: URL
    ) async throws {
        try await recorder.startQuestionDictationRecording(to: url)
    }

    func testMicrophoneValidationFailureRestartsCaptureOnceThenReportsFailure() async throws {
        let fake = try FakeMicrophoneCaptureSession()
        let recorder = makeRecorder(capture: fake)
        recorder.microphonePermissionValidator = {}
        recorder.activeRecordingSource = .microphone
        let reported = CapturedRecordingError()
        recorder.onRecordingError = { reported.set($0) }
        let url = makeTemporaryURL()

        try await recorder.startMicrophoneCaptureRecording(to: url, retryCount: 0)
        let firstSessionID = try XCTUnwrap(recorder.activeValidationSessionID)

        await recorder.handleValidationTimeout(url: url, source: .microphone, retryCount: 0, sessionID: firstSessionID)

        XCTAssertEqual(fake.recordedDeviceUIDs.count, 2)
        XCTAssertTrue(recorder.isRecording)
        XCTAssertNil(reported.value)

        let secondSessionID = try XCTUnwrap(recorder.activeValidationSessionID)
        XCTAssertNotEqual(firstSessionID, secondSessionID)
        await recorder.handleValidationTimeout(url: url, source: .microphone, retryCount: 1, sessionID: secondSessionID)

        XCTAssertEqual(fake.recordedDeviceUIDs.count, 2)
        guard case .recordingValidationFailed? = reported.value as? AudioRecorderError else {
            return XCTFail("Expected recordingValidationFailed, got \(String(describing: reported.value))")
        }
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(fake.stopCallCount, 2)
    }

    func testStopDuringMicrophoneCaptureRestartKeepsSessionUntilStop() async throws {
        let fake = try FakeMicrophoneCaptureSession()
        fake.closeStopGate()
        defer { fake.openStopGate() }
        let recorder = makeRecorder(capture: fake)
        recorder.activeRecordingSource = .microphone
        let reported = CapturedRecordingError()
        recorder.onRecordingError = { reported.set($0) }
        let url = makeTemporaryURL()

        try await recorder.startMicrophoneCaptureRecording(to: url, retryCount: 0)
        let sessionID = try XCTUnwrap(recorder.activeValidationSessionID)
        var published: [Bool] = []
        let cancellable = recorder.isRecordingPublisher.sink { published.append($0) }
        defer { cancellable.cancel() }

        let restart = Task {
            await recorder.handleValidationTimeout(url: url, source: .microphone, retryCount: 0, sessionID: sessionID)
        }
        await waitUntil(timeout: .seconds(5), message: "Restart should become visible.") {
            recorder.restartingCaptureURL == url
        }
        XCTAssertEqual(published, [true])

        let stoppedURL = await recorder.stopRecording()
        fake.openStopGate()
        await restart.value

        XCTAssertEqual(stoppedURL, url)
        XCTAssertEqual(published, [true, false])
        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.restartingCaptureURL)
        XCTAssertNil(reported.value)
    }

    func testMissingPreferredMicrophoneFallsBackToDefault() async throws {
        let fake = try FakeMicrophoneCaptureSession()
        let recorder = makeRecorder(capture: fake)

        try await recorder.startMicrophoneCaptureSession(fake, preferredUID: "missing-device")

        XCTAssertEqual(recorder.activeMicrophoneDeviceName, fake.simulatedDefaultDevice.name)
        XCTAssertTrue(recorder.activeMicrophoneDidFallBackToDefault)
        XCTAssertEqual(fake.recordedDeviceUIDs, ["missing-device"])
    }

    func testMissingStoredPreferenceFallsBackThroughRecordingStart() async throws {
        let settings = AppSettingsStore.shared
        settings.resetToDefaults()
        settings.useSystemDefaultInput = false
        settings.microphoneWhenChargingUID = "unplugged-mic-uid"
        settings.microphoneOnBatteryUID = "unplugged-mic-uid"
        defer { settings.resetToDefaults() }
        let fake = try FakeMicrophoneCaptureSession()
        let recorder = makeRecorder(capture: fake)
        recorder.validationInterval = 60
        recorder.activeRecordingSource = .microphone
        let url = makeTemporaryURL()

        try await recorder.startMicrophoneCaptureRecording(to: url, retryCount: 0)

        XCTAssertEqual(recorder.activeMicrophoneDeviceName, fake.simulatedDefaultDevice.name)
        XCTAssertTrue(recorder.activeMicrophoneDidFallBackToDefault)
        XCTAssertEqual(fake.recordedDeviceUIDs, ["unplugged-mic-uid"])
    }

    func testResolvedPreferredMicrophoneReportsNoFallback() async throws {
        let fake = try FakeMicrophoneCaptureSession()
        fake.simulatedDevicesByUID = ["usb-mic": FakeCaptureDevice(uid: "usb-mic", name: "Fake USB Microphone")]
        let recorder = makeRecorder(capture: fake)

        try await recorder.startMicrophoneCaptureSession(fake, preferredUID: "usb-mic")

        XCTAssertEqual(recorder.activeMicrophoneDeviceName, "Fake USB Microphone")
        XCTAssertFalse(recorder.activeMicrophoneDidFallBackToDefault)
    }

    func testActiveMicrophoneStateClearsAfterStop() async throws {
        let fake = try FakeMicrophoneCaptureSession()
        let recorder = makeRecorder(capture: fake)
        let url = makeTemporaryURL()
        recorder.activeRecordingSource = .microphone

        try await recorder.startMicrophoneCaptureRecording(to: url, retryCount: 0)
        XCTAssertEqual(recorder.activeMicrophoneDeviceName, fake.simulatedDefaultDevice.name)
        XCTAssertFalse(recorder.activeMicrophoneDidFallBackToDefault)

        _ = await recorder.stopRecording()
        XCTAssertNil(recorder.activeMicrophoneDeviceName)
        XCTAssertFalse(recorder.activeMicrophoneDidFallBackToDefault)
    }

    func testMicrophoneCaptureFileExtensionMatchesConfiguredAudioFormat() async throws {
        try AppSettingsTestIsolationLock.acquire()
        defer { AppSettingsTestIsolationLock.release() }
        let settings = AppSettingsStore.shared
        let originalFormat = settings.audioFormat
        defer { settings.audioFormat = originalFormat }

        for format in [AppSettingsStore.AudioFormat.m4a, AppSettingsStore.AudioFormat.wav] {
            settings.audioFormat = format
            let url = format.temporaryRecordingURL(prefix: "mic-format-test")
            ownedURLs.append(url)
            XCTAssertEqual(url.pathExtension, format.fileExtension)

            let fake = try FakeMicrophoneCaptureSession()
            let recorder = makeRecorder(capture: fake)
            try await recorder.startMicrophoneCaptureRecording(to: url, retryCount: 0)
            fake.emitValidBuffer()
            await waitForValidBuffer(recorder)

            let stoppedURL = await recorder.stopRecording()
            XCTAssertEqual(stoppedURL?.pathExtension, format.fileExtension)
            let writtenFile = try AVAudioFile(forReading: url)
            XCTAssertGreaterThan(writtenFile.length, 0)
        }
    }

    func testStopDuringMicrophoneStartupClosesTheCaptureSession() async throws {
        let fake = try FakeMicrophoneCaptureSession()
        weak var weakRecorder: DictationRecorder?
        let recorder = DictationRecorder(microphoneCaptureFactory: { onBuffer, onFailure in
            fake.setCallbacks(onBuffer: onBuffer, onFailure: onFailure)
            MainActor.assumeIsolated { weakRecorder?.captureGeneration &+= 1 }
            return fake
        })
        weakRecorder = recorder
        self.recorder = recorder
        recorder.validationInterval = 60
        recorder.microphonePermissionValidator = {}

        do {
            try await recorder.startRecording(to: makeTemporaryURL(), source: .microphone)
            XCTFail("A stop during startup should cancel the start.")
        } catch is CancellationError {}

        XCTAssertEqual(fake.recordedDeviceUIDs.count, 1)
        XCTAssertEqual(fake.stopCallCount, 1)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.currentRecordingURL)
    }

    private func makeRecorder(capture fake: FakeMicrophoneCaptureSession) -> DictationRecorder {
        let recorder = DictationRecorder(microphoneCaptureFactory: { onBuffer, onFailure in
            fake.setCallbacks(onBuffer: onBuffer, onFailure: onFailure)
            return fake
        })
        self.recorder = recorder
        recorder.validationInterval = 60
        return recorder
    }

    private func makeTemporaryURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mic-capture-test-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        ownedURLs.append(url)
        return url
    }

    private func waitForValidBuffer(_ recorder: DictationRecorder) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while await !recorder.worker.getHasReceivedValidBuffer() {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for a valid buffer.")
                return
            }
            await Task.yield()
        }
    }
}

final class FakeMicrophoneCaptureSession: MicrophoneCaptureSessionProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var startedUIDs: [String?] = []
    private var stops = 0
    private var stopGateClosed = false
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []
    private var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private var onFailure: (@Sendable (Error) -> Void)?
    let format: AVAudioFormat
    var simulatedDefaultDevice = FakeCaptureDevice(uid: "fake-default-uid", name: "Fake Default Microphone")
    var simulatedDevicesByUID: [String: FakeCaptureDevice] = [:]

    init() throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000.0,
            channels: 2,
            interleaved: false
        ) else {
            throw FakeMicrophoneCaptureSessionError.unableToMakeFormat
        }
        self.format = format
    }

    var recordedDeviceUIDs: [String?] {
        lock.withLock { startedUIDs }
    }

    var stopCallCount: Int {
        lock.withLock { stops }
    }

    func setCallbacks(
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onFailure: @escaping @Sendable (Error) -> Void
    ) {
        lock.withLock {
            self.onBuffer = onBuffer
            self.onFailure = onFailure
        }
    }

    // swiftlint:disable:next async_without_await - justified: protocol requires async; fake start records synchronously.
    func start(deviceUID: String?) async throws -> MicrophoneCaptureStartResult {
        lock.withLock { startedUIDs.append(deviceUID) }
        let resolved = deviceUID.flatMap { simulatedDevicesByUID[$0] }
        let active = resolved ?? simulatedDefaultDevice
        return MicrophoneCaptureStartResult(
            requestedDeviceUID: deviceUID,
            activeDeviceName: active.name,
            didFallBackToDefault: deviceUID != nil && resolved == nil
        )
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            let mustWait = lock.withLock {
                stops += 1
                if stopGateClosed { stopWaiters.append(continuation) }
                return stopGateClosed
            }
            if !mustWait { continuation.resume() }
        }
    }

    func closeStopGate() {
        lock.withLock { stopGateClosed = true }
    }

    func openStopGate() {
        let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            stopGateClosed = false
            let waiters = stopWaiters
            stopWaiters = []
            return waiters
        }
        waiters.forEach { $0.resume() }
    }

    func emitValidBuffer(frameCount: AVAudioFrameCount = 2048) {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        lock.withLock { onBuffer }?(buffer)
    }

    func fail(_ error: Error) {
        lock.withLock { onFailure }?(error)
    }
}

enum FakeMicrophoneCaptureSessionError: Error {
    case unableToMakeFormat
    case simulatedFailure
}

struct FakeCaptureDevice: Sendable {
    let uid: String
    let name: String
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0

    var count: Int {
        lock.withLock { storedCount }
    }

    var isEmpty: Bool {
        lock.withLock { storedCount == 0 }
    }

    func increment() {
        lock.withLock { storedCount += 1 }
    }
}

private final class CapturedRecordingError: @unchecked Sendable {
    private let lock = NSLock()
    private var storedError: Error?

    var value: Error? {
        lock.withLock { storedError }
    }

    func set(_ error: Error) {
        lock.withLock { storedError = error }
    }
}

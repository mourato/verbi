import AVFoundation
@testable import VerbiCore
@testable import VerbiCoreAudio
@testable import VerbiCoreInfrastructure
import XCTest

@MainActor
final class AudioRecorderMicrophoneCaptureTests: XCTestCase {
    private var recorder: AudioRecorder?
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

    func testMicrophoneCaptureValidationWithoutAudioStartsFallbackRecorder() async throws {
        let fake = try FakeMicrophoneCaptureSession()
        let recorder = makeRecorder(capture: fake)
        recorder.validationInterval = 0.05
        recorder.activeRecordingSource = .microphone
        let url = makeTemporaryURL()

        try await recorder.startMicrophoneCaptureRecording(to: url, retryCount: 0)

        await waitUntil(timeout: .seconds(5), message: "Validation should start the fallback recorder.") {
            recorder.fallbackRecorder != nil
        }

        XCTAssertNotNil(recorder.fallbackRecorder)
        XCTAssertTrue(recorder.isRecording)
        XCTAssertEqual(recorder.currentRecordingURL, url)
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
        XCTAssertNil(recorder.fallbackRecorder)
        XCTAssertNil(reported.value)
    }

    private func makeRecorder(capture fake: FakeMicrophoneCaptureSession) -> AudioRecorder {
        let recorder = AudioRecorder(microphoneCaptureFactory: { onBuffer, onFailure in
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

    private func waitForValidBuffer(_ recorder: AudioRecorder) async {
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
    func start(deviceUID: String?) async throws {
        lock.withLock { startedUIDs.append(deviceUID) }
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

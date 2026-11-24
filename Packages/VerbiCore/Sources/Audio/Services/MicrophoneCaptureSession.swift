@preconcurrency import AVFoundation
import Foundation

final class MicrophoneCaptureSession: NSObject, MicrophoneCaptureSessionProtocol, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    static let sampleRate = 48000.0
    static let chunkFrameCount: AVAudioFrameCount = 2048

    enum StartError: Error {
        case deviceUnavailable
        case configurationRejected
    }

    let format: AVAudioFormat
    private let captureFormat: AVAudioFormat
    private let queue = DispatchQueue(label: "com.mourato.verbi.microphone-capture")
    private let lifecycleQueue = DispatchQueue(label: "com.mourato.verbi.microphone-capture-lifecycle")
    private let session = AVCaptureSession()
    private let onBuffer: @Sendable (AVAudioPCMBuffer) -> Void
    private let onFailure: @Sendable (Error) -> Void
    private var pending: AVAudioPCMBuffer?
    private var observers: [NSObjectProtocol] = []

    init(
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onFailure: @escaping @Sendable (Error) -> Void = { _ in }
    ) throws {
        guard let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: Self.sampleRate,
                  channels: 2,
                  interleaved: false
              ),
              let captureFormat = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: Self.sampleRate,
                  channels: 1,
                  interleaved: false
              )
        else { throw StartError.configurationRejected }
        self.format = format
        self.captureFormat = captureFormat
        self.onBuffer = onBuffer
        self.onFailure = onFailure
    }

    func start(deviceUID: String?) async throws -> MicrophoneCaptureStartResult {
        let requestedDevice = deviceUID.flatMap { AVCaptureDevice(uniqueID: $0) }
        let device = requestedDevice ?? AVCaptureDevice.default(for: .audio)
        guard let device else { throw StartError.deviceUnavailable }
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true,
            AVLinearPCMIsBigEndianKey: false
        ]
        try await onLifecycleQueue { [self] in
            try configureAndRun(input: input, output: output)
            observeFailures(of: device)
        }
        return MicrophoneCaptureStartResult(
            requestedDeviceUID: deviceUID,
            activeDeviceUID: device.uniqueID,
            activeDeviceName: device.localizedName,
            usedRequestedDevice: requestedDevice != nil || deviceUID == nil
        )
    }

    func stop() async {
        await onLifecycleQueue { [self] in
            removeObservers()
            session.stopRunning()
            queue.sync {
                if let pending, pending.frameLength > 0 {
                    onBuffer(pending)
                }
                pending = nil
            }
        }
    }

    private func configureAndRun(input: AVCaptureDeviceInput, output: AVCaptureAudioDataOutput) throws {
        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            throw StartError.configurationRejected
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        output.setSampleBufferDelegate(self, queue: queue)
        session.startRunning()
    }

    private func onLifecycleQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            lifecycleQueue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }

    private func onLifecycleQueue(_ work: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { continuation in
            lifecycleQueue.async {
                work()
                continuation.resume()
            }
        }
    }

    private func observeFailures(of device: AVCaptureDevice) {
        let center = NotificationCenter.default
        let onFailure = onFailure
        observers = [
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { note in
                let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error
                onFailure(error ?? StartError.deviceUnavailable)
            },
            center.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: device, queue: nil) { _ in
                onFailure(StartError.deviceUnavailable)
            }
        ]
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    func captureOutput(
        _: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from _: AVCaptureConnection
    ) {
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: captureFormat, frameCapacity: frameCount)
        else { return }
        buffer.frameLength = frameCount
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else { return }
        append(buffer)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let source = buffer.floatChannelData?[0] else { return }
        var offset: AVAudioFrameCount = 0
        while offset < buffer.frameLength {
            guard let chunk = pending ?? AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Self.chunkFrameCount)
            else { return }
            let copied = min(chunk.frameCapacity - chunk.frameLength, buffer.frameLength - offset)
            copy(source + Int(offset), count: copied, into: chunk)
            offset += copied
            emitOrKeep(chunk)
        }
    }

    private func copy(_ source: UnsafePointer<Float>, count: AVAudioFrameCount, into chunk: AVAudioPCMBuffer) {
        guard let channels = chunk.floatChannelData else { return }
        for channel in 0 ..< Int(format.channelCount) {
            (channels[channel] + Int(chunk.frameLength)).update(from: source, count: Int(count))
        }
        chunk.frameLength += count
    }

    private func emitOrKeep(_ chunk: AVAudioPCMBuffer) {
        guard chunk.frameLength == chunk.frameCapacity else {
            pending = chunk
            return
        }
        onBuffer(chunk)
        pending = nil
    }
}

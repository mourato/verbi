@preconcurrency import AVFoundation
import Foundation

final class MicrophoneCaptureSession: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    static let sampleRate = 48000.0
    static let chunkFrameCount: AVAudioFrameCount = 2048

    enum StartError: Error {
        case deviceUnavailable
        case configurationRejected
    }

    let format: AVAudioFormat
    private let captureFormat: AVAudioFormat
    private let queue = DispatchQueue(label: "com.mourato.verbi.microphone-capture")
    private let session = AVCaptureSession()
    private let onBuffer: @Sendable (AVAudioPCMBuffer) -> Void
    private var pending: AVAudioPCMBuffer?

    init(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
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
    }

    func start(deviceUID: String?) throws {
        let device = deviceUID.flatMap { AVCaptureDevice(uniqueID: $0) } ?? AVCaptureDevice.default(for: .audio)
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
        try queue.sync {
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
    }

    func stop() {
        queue.sync {
            session.stopRunning()
            if let pending, pending.frameLength > 0 {
                onBuffer(pending)
            }
            pending = nil
        }
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

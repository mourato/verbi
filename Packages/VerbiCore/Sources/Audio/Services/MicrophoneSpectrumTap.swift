@preconcurrency import AVFoundation
import Foundation
import os.lock

/// Visualization-only microphone tap for the `AVAudioRecorder` path, which
/// exposes meter values but no samples. Opens the default input at 16kHz mono
/// Float32 (the spectrum kernel's reference window: 512 samples = 32ms) and
/// keeps the latest band levels. Never writes audio; if the session cannot
/// start, `latestLevels` stays empty and the indicator keeps its
/// volume-driven fallback.
///
/// `@unchecked Sendable`: the capture session and sample history are confined
/// to `queue`; published levels are guarded by `OSAllocatedUnfairLock`.
final class MicrophoneSpectrumTap: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private static let sampleRate = 16000.0
    private static let windowSampleCount = 512

    /// AVFoundation delivers sample buffers on a dispatch queue, and
    /// `startRunning()` blocks, so session control shares that serial queue.
    private let queue = DispatchQueue(label: "com.mourato.verbi.microphone-spectrum-tap")
    private let session = AVCaptureSession()
    private var samples: [Float] = []
    private let levels = OSAllocatedUnfairLock<[Float]>(initialState: [])

    var latestLevels: [Float] {
        levels.withLock { $0 }
    }

    func start() {
        queue.async { [self] in
            guard let device = AVCaptureDevice.default(for: .audio),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input)
            else { return }
            let output = AVCaptureAudioDataOutput()
            output.audioSettings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: Self.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false
            ]
            guard session.canAddOutput(output) else { return }
            session.addInput(input)
            session.addOutput(output)
            output.setSampleBufferDelegate(self, queue: queue)
            session.startRunning()
        }
    }

    func stop() {
        queue.async { [self] in
            session.stopRunning()
            samples.removeAll()
        }
        levels.withLock { $0 = [] }
    }

    func captureOutput(
        _: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from _: AVCaptureConnection
    ) {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var length = 0
        var pointer: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(
            block,
            atOffset: 0,
            lengthAtOffsetOut: &length,
            totalLengthOut: nil,
            dataPointerOut: &pointer
        ) == kCMBlockBufferNoErr, let pointer else { return }

        let count = length / MemoryLayout<Float>.size
        pointer.withMemoryRebound(to: Float.self, capacity: count) {
            samples.append(contentsOf: UnsafeBufferPointer(start: $0, count: count))
        }
        if samples.count > Self.windowSampleCount {
            samples.removeFirst(samples.count - Self.windowSampleCount)
        }

        let bands = SwiftSpectrumKernel.levels(forMonoSamples: samples, sampleRate: Self.sampleRate)
        levels.withLock { $0 = bands }
    }
}

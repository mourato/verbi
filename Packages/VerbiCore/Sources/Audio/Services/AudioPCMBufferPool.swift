@preconcurrency import AVFoundation
import Foundation
import os.lock

/// Reuses `AVAudioPCMBuffer` instances to reduce allocation churn on the
/// system-audio capture path.
final class AudioPCMBufferPool: @unchecked Sendable {
    static let shared = AudioPCMBufferPool()

    private struct BufferKey: Hashable {
        let sampleRate: Int
        let channelCount: AVAudioChannelCount
        let commonFormatRawValue: UInt
        let isInterleaved: Bool
        let frameCapacity: Int

        init(format: AVAudioFormat, frameCapacity: AVAudioFrameCount) {
            sampleRate = Int(format.sampleRate.rounded())
            channelCount = format.channelCount
            commonFormatRawValue = format.commonFormat.rawValue
            isInterleaved = format.isInterleaved
            self.frameCapacity = Int(frameCapacity)
        }

        init(buffer: AVAudioPCMBuffer) {
            self.init(format: buffer.format, frameCapacity: buffer.frameCapacity)
        }
    }

    private struct State {
        var storage: [BufferKey: [AVAudioPCMBuffer]] = [:]
    }

    private enum Constants {
        static let maxBuffersPerKey = 24
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    private init() {}

    func checkout(format: AVAudioFormat, frameCapacity: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        let key = BufferKey(format: format, frameCapacity: frameCapacity)
        return state.withLock { state in
            guard var bucket = state.storage[key], !bucket.isEmpty else {
                return nil
            }
            let buffer = bucket.removeLast()
            state.storage[key] = bucket.isEmpty ? nil : bucket
            return buffer
        }
    }

    func release(_ buffer: AVAudioPCMBuffer) {
        let key = BufferKey(buffer: buffer)
        buffer.frameLength = 0

        state.withLock { state in
            var bucket = state.storage[key, default: []]
            guard bucket.count < Constants.maxBuffersPerKey else {
                return
            }
            bucket.append(buffer)
            state.storage[key] = bucket
        }
    }
}

/// Tracks pooled buffers that are currently in-flight and returns them to the pool
/// once consumers are done with them.
final class AudioPCMBufferLeaseRegistry: @unchecked Sendable {
    static let shared = AudioPCMBufferLeaseRegistry()

    private struct State {
        var leasedBuffers: [ObjectIdentifier: AVAudioPCMBuffer] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    private init() {}

    func register(buffer: AVAudioPCMBuffer) {
        let identifier = ObjectIdentifier(buffer)

        state.withLock { state in
            state.leasedBuffers[identifier] = buffer
        }
    }

    func releaseIfNeeded(for buffer: AVAudioPCMBuffer) {
        let identifier = ObjectIdentifier(buffer)

        let leasedBuffer = state.withLock { state -> AVAudioPCMBuffer? in
            state.leasedBuffers.removeValue(forKey: identifier)
        }

        if let leasedBuffer {
            AudioPCMBufferPool.shared.release(leasedBuffer)
        }
    }
}

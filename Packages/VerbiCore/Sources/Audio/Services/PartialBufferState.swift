@preconcurrency import AVFoundation
import Foundation
import os.lock

public final class PartialBufferState: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()

    private var buffer: AVAudioPCMBuffer?
    private var readOffset: Int = 0

    public init() {}

    public var framesRemaining: Int {
        lock.withLock {
            guard let buffer else { return 0 }
            return Int(buffer.frameLength) - self.readOffset
        }
    }

    public var hasPartial: Bool {
        lock.withLock {
            guard let buffer else { return false }
            return self.readOffset < Int(buffer.frameLength)
        }
    }

    public func setBuffer(_ buffer: AVAudioPCMBuffer, offset: Int = 0) {
        lock.withLock {
            if let existingBuffer = self.buffer, existingBuffer !== buffer {
                AudioPCMBufferLeaseRegistry.shared.releaseIfNeeded(for: existingBuffer)
            }
            self.buffer = buffer
            self.readOffset = offset
        }
    }

    @discardableResult
    public func consume(
        maxFrames: Int,
        into destBuffers: UnsafeMutableAudioBufferListPointer,
        destOffset: Int
    ) -> Int {
        lock.withLock {
            guard let buffer, self.readOffset < Int(buffer.frameLength) else {
                return 0
            }

            let available = Int(buffer.frameLength) - self.readOffset
            let framesToCopy = min(maxFrames, available)

            guard framesToCopy > 0, let srcChannels = buffer.floatChannelData else {
                return 0
            }

            let bufferChannelCount = Int(buffer.format.channelCount)
            let channelsToCopy = min(min(2, bufferChannelCount), destBuffers.count)

            for ch in 0 ..< channelsToCopy {
                guard ch < 2 else { break }
                let destBuffer = destBuffers[ch]
                guard destBuffer.mData != nil, destBuffer.mDataByteSize > 0 else {
                    continue
                }
                let src = srcChannels[ch].advanced(by: self.readOffset)

                if let destStart = destBuffer.mData?.assumingMemoryBound(to: Float.self) {
                    let destPtr = UnsafeMutableBufferPointer(
                        start: destStart.advanced(by: destOffset),
                        count: framesToCopy
                    )
                    let srcPtr = UnsafeBufferPointer(start: src, count: framesToCopy)
                    _ = destPtr.initialize(from: srcPtr)
                }
            }

            self.readOffset += framesToCopy

            if self.readOffset >= Int(buffer.frameLength) {
                self.buffer = nil
                self.readOffset = 0
                AudioPCMBufferLeaseRegistry.shared.releaseIfNeeded(for: buffer)
            }

            return framesToCopy
        }
    }

    public func clear() {
        lock.withLock {
            if let currentBuffer = self.buffer {
                AudioPCMBufferLeaseRegistry.shared.releaseIfNeeded(for: currentBuffer)
            }
            self.buffer = nil
            self.readOffset = 0
        }
    }

    public static func copy(
        from buffer: AVAudioPCMBuffer,
        srcOffset: Int,
        maxFrames: Int,
        into destBuffers: UnsafeMutableAudioBufferListPointer,
        destOffset: Int
    ) -> Int {
        let available = Int(buffer.frameLength) - srcOffset
        let framesToCopy = min(maxFrames, available)

        guard framesToCopy > 0, let srcChannels = buffer.floatChannelData else {
            return 0
        }

        let bufferChannelCount = Int(buffer.format.channelCount)
        let channelsToCopy = min(min(2, bufferChannelCount), destBuffers.count)

        for ch in 0 ..< channelsToCopy {
            guard ch < 2 else { break }
            let destBuffer = destBuffers[ch]
            guard destBuffer.mData != nil, destBuffer.mDataByteSize > 0 else {
                continue
            }
            let src = srcChannels[ch].advanced(by: srcOffset)

            if let destStart = destBuffer.mData?.assumingMemoryBound(to: Float.self) {
                let destPtr = UnsafeMutableBufferPointer(
                    start: destStart.advanced(by: destOffset),
                    count: framesToCopy
                )
                let srcPtr = UnsafeBufferPointer(start: src, count: framesToCopy)
                _ = destPtr.initialize(from: srcPtr)
            }
        }
        return framesToCopy
    }
}

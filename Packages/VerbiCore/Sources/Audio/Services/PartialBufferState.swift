@preconcurrency import AVFoundation
import Foundation
import os.lock

/// Thread-safe tracker for partially consumed audio buffers.
/// Used by `AVAudioSourceNode` to preserve frames when a buffer is larger than
/// the requested `frameCount`, ensuring no audio data is lost between render cycles.
///
/// This class is `@unchecked Sendable` because it protects all mutable state
/// with `OSAllocatedUnfairLock`, which is safe for audio thread usage.
public final class PartialBufferState: @unchecked Sendable {
    // MARK: - State

    private let lock = OSAllocatedUnfairLock()

    private var buffer: AVAudioPCMBuffer?
    private var readOffset: Int = 0

    // MARK: - Lifecycle

    public init() {}

    // MARK: - Public API

    /// Number of frames remaining in the current partial buffer.
    public var framesRemaining: Int {
        lock.withLock {
            guard let buffer else { return 0 }
            return Int(buffer.frameLength) - self.readOffset
        }
    }

    /// Whether there is a partial buffer with unconsumed frames.
    public var hasPartial: Bool {
        lock.withLock {
            guard let buffer else { return false }
            return self.readOffset < Int(buffer.frameLength)
        }
    }

    /// Sets a new buffer to consume from.
    /// - Parameters:
    ///   - buffer: The audio buffer to consume from.
    ///   - offset: Starting offset (default 0).
    public func setBuffer(_ buffer: AVAudioPCMBuffer, offset: Int = 0) {
        lock.withLock {
            if let existingBuffer = self.buffer, existingBuffer !== buffer {
                AudioPCMBufferLeaseRegistry.shared.releaseIfNeeded(for: existingBuffer)
            }
            self.buffer = buffer
            self.readOffset = offset
        }
    }

    /// Consumes frames from the current partial buffer into the destination buffer list.
    /// - Parameters:
    ///   - maxFrames: Maximum number of frames to consume.
    ///   - destBuffers: Destination audio buffer list pointer.
    ///   - destOffset: Offset in the destination buffer to start writing.
    /// - Returns: Number of frames actually consumed.
    @discardableResult
    public func consume(
        maxFrames: Int,
        into destBuffers: UnsafeMutableAudioBufferListPointer,
        destOffset: Int
    ) -> Int {
        lock.withLock {
            // CRITICAL: No I/O operations in audio callback path - can cause crashes
            guard let buffer, self.readOffset < Int(buffer.frameLength) else {
                return 0
            }

            let available = Int(buffer.frameLength) - self.readOffset
            let framesToCopy = min(maxFrames, available)

            guard framesToCopy > 0, let srcChannels = buffer.floatChannelData else {
                return 0
            }

            // CRITICAL FIX: Don't access destBuffers.count as it may crash on uninitialized structure
            // Use the buffer's channel count and validate destBuffers access individually
            let bufferChannelCount = Int(buffer.format.channelCount)
            let channelsToCopy = min(min(2, bufferChannelCount), destBuffers.count)

            // Copy each channel
            for ch in 0 ..< channelsToCopy {
                guard ch < 2 else { break } // Safety check for destBuffers access
                let destBuffer = destBuffers[ch]
                guard destBuffer.mData != nil, destBuffer.mDataByteSize > 0 else {
                    continue
                }
                let src = srcChannels[ch].advanced(by: self.readOffset)

                // Optimized memcpy via UnsafeBufferPointer
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

            // Clear buffer reference if fully consumed
            if self.readOffset >= Int(buffer.frameLength) {
                self.buffer = nil
                self.readOffset = 0
                AudioPCMBufferLeaseRegistry.shared.releaseIfNeeded(for: buffer)
            }

            return framesToCopy
        }
    }

    /// Clears the partial buffer state.
    public func clear() {
        lock.withLock {
            if let currentBuffer = self.buffer {
                AudioPCMBufferLeaseRegistry.shared.releaseIfNeeded(for: currentBuffer)
            }
            self.buffer = nil
            self.readOffset = 0
        }
    }

    // MARK: - Static Helpers

    /// Static helper to copy frames from a source buffer into a destination buffer list.
    /// Does not use or modify any instance state. Essential for avoiding heap allocations
    /// in real-time audio render callbacks.
    /// - Parameters:
    ///   - buffer: The source audio buffer.
    ///   - srcOffset: The offset within the source buffer to start copying from.
    ///   - maxFrames: Maximum number of frames to copy.
    ///   - destBuffers: The destination buffer list pointer.
    ///   - destOffset: The offset within the destination buffer to start writing.
    /// - Returns: Number of frames actually copied.
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

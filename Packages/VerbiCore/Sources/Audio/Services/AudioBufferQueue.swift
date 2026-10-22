@preconcurrency import AVFoundation
import Foundation
import os.lock

/// A thread-safe, fixed-size Circular Buffer (Ring Buffer) for `AVAudioPCMBuffer`.
/// Designed for high-performance audio bridging between `ScreenCaptureKit` (Push) and `AVAudioSourceNode` (Pull).
/// Uses `OSAllocatedUnfairLock` for real-time safe thread safety.
public final class AudioBufferQueue: @unchecked Sendable {
    // MARK: - State

    private struct State {
        var bufferStorage: [AVAudioPCMBuffer?]
        var head: Int = 0 // Write index
        var tail: Int = 0 // Read index
        var count: Int = 0 // Current items
        var droppedFrameCount: Int64 = 0
    }

    private let state: OSAllocatedUnfairLock<State>
    private let capacity: Int

    // MARK: - Lifecycle

    /// Initializes a ring buffer with a specific capacity (number of chunks).
    /// - Parameter capacity: Maximum number of buffers to hold. Default is 50 (~5-10s depending on buffer size).
    public init(capacity: Int = 50) {
        self.capacity = capacity
        let initialStorage = [AVAudioPCMBuffer?](repeating: nil, count: capacity)
        state = OSAllocatedUnfairLock(initialState: State(bufferStorage: initialStorage))
    }

    // MARK: - Public API

    /// Enqueues a buffer. STRICTLY NON-BLOCKING (spins/waits very briefly).
    /// If full, overwrites the oldest data (Drop Oldest strategy) to maintain real-time currency.
    public func enqueue(_ buffer: AVAudioPCMBuffer) {
        state.withLock { state in
            if state.count >= capacity {
                // Buffer full: Drop oldest (tail) to make space
                // This ensures we always have fresh data and don't lag behind
                if let droppedBuffer = state.bufferStorage[state.tail] {
                    AudioPCMBufferLeaseRegistry.shared.releaseIfNeeded(for: droppedBuffer)
                }
                state.bufferStorage[state.tail] = nil // Release ref
                state.tail = (state.tail + 1) % capacity
                state.count -= 1
                state.droppedFrameCount += Int64(buffer.frameLength)
            }

            // Write to head
            state.bufferStorage[state.head] = buffer
            state.head = (state.head + 1) % capacity
            state.count += 1
        }
    }

    /// Dequeues a buffer.
    /// - Returns: The next buffer, or nil if empty.
    public func dequeue() -> AVAudioPCMBuffer? {
        state.withLock { state in
            guard state.count >= 1 else {
                return nil
            }

            let buffer = state.bufferStorage[state.tail]

            state.bufferStorage[state.tail] = nil
            state.tail = (state.tail + 1) % capacity
            state.count -= 1

            return buffer
        }
    }

    // MARK: - Private Helpers

    /// Clears the queue.
    public func clear() {
        state.withLock { state in
            for i in 0 ..< capacity {
                if let queuedBuffer = state.bufferStorage[i] {
                    AudioPCMBufferLeaseRegistry.shared.releaseIfNeeded(for: queuedBuffer)
                }
                state.bufferStorage[i] = nil
            }
            state.head = 0
            state.tail = 0
            state.count = 0
            state.droppedFrameCount = 0
        }
    }

    /// Returns debug statistics (thread-safe).
    public var stats: (count: Int, dropped: Int64) {
        state.withLock { ($0.count, $0.droppedFrameCount) }
    }

    /// Returns whether the queue is empty.
    public var isEmpty: Bool {
        state.withLock { $0.count < 1 }
    }
}

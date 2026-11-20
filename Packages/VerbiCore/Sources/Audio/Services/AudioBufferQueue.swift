@preconcurrency import AVFoundation
import Foundation
import os.lock

public final class AudioBufferQueue: @unchecked Sendable {
    private struct State {
        var bufferStorage: [AVAudioPCMBuffer?]
        var head: Int = 0
        var tail: Int = 0
        var count: Int = 0
        var droppedFrameCount: Int64 = 0
    }

    private let state: OSAllocatedUnfairLock<State>
    private let capacity: Int

    public init(capacity: Int = 50) {
        self.capacity = capacity
        let initialStorage = [AVAudioPCMBuffer?](repeating: nil, count: capacity)
        state = OSAllocatedUnfairLock(initialState: State(bufferStorage: initialStorage))
    }

    public func enqueue(_ buffer: AVAudioPCMBuffer) {
        state.withLock { state in
            if state.count >= capacity {
                if let droppedBuffer = state.bufferStorage[state.tail] {
                    AudioPCMBufferLeaseRegistry.shared.releaseIfNeeded(for: droppedBuffer)
                }
                state.bufferStorage[state.tail] = nil
                state.tail = (state.tail + 1) % capacity
                state.count -= 1
                state.droppedFrameCount += Int64(buffer.frameLength)
            }

            state.bufferStorage[state.head] = buffer
            state.head = (state.head + 1) % capacity
            state.count += 1
        }
    }

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

    public var stats: (count: Int, dropped: Int64) {
        state.withLock { ($0.count, $0.droppedFrameCount) }
    }

    public var isEmpty: Bool {
        state.withLock { $0.count < 1 }
    }
}

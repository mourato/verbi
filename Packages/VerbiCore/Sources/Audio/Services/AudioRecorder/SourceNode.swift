@preconcurrency import AVFoundation
import CoreAudio
import Foundation

extension AudioRecorder {
    nonisolated func createSystemSourceNode(
        queue: AudioBufferQueue,
        partialState: PartialBufferState
    ) -> AVAudioSourceNode {
        AVAudioSourceNode { @Sendable [queue, partialState] _, _, frameCount, audioBufferList -> OSStatus in
            self.validateCallbackInputs(
                frameCount: frameCount,
                audioBufferList: audioBufferList,
                queue: queue,
                partialState: partialState
            )
        }
    }

    nonisolated func validateCallbackInputs(
        frameCount: UInt32,
        audioBufferList: UnsafeMutablePointer<AudioBufferList>,
        queue: AudioBufferQueue,
        partialState: PartialBufferState
    ) -> OSStatus {
        guard frameCount > 0 else {
            return -50
        }

        return processAudioBuffers(
            frameCount: frameCount,
            audioBufferList: audioBufferList,
            queue: queue,
            partialState: partialState
        )
    }

    nonisolated func processAudioBuffers(
        frameCount: UInt32,
        audioBufferList: UnsafeMutablePointer<AudioBufferList>,
        queue: AudioBufferQueue,
        partialState: PartialBufferState
    ) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let targetFrames = Int(frameCount)
        var framesFilled = 0

        if partialState.hasPartial {
            framesFilled += partialState.consume(maxFrames: targetFrames, into: buffers, destOffset: 0)
        }

        while framesFilled < targetFrames {
            guard let nextBuffer = queue.dequeue() else {
                break
            }

            let framesToCopy = min(Int(nextBuffer.frameLength), targetFrames - framesFilled)

            let copied = PartialBufferState.copy(
                from: nextBuffer,
                srcOffset: 0,
                maxFrames: framesToCopy,
                into: buffers,
                destOffset: framesFilled
            )

            framesFilled += copied

            if copied < Int(nextBuffer.frameLength) {
                partialState.setBuffer(nextBuffer, offset: copied)
            } else {
                AudioPCMBufferLeaseRegistry.shared.releaseIfNeeded(for: nextBuffer)
            }
        }

        if framesFilled < targetFrames {
            fillBuffersWithSilence(
                buffers: buffers,
                bufferCount: 2,
                targetFrames: targetFrames - framesFilled,
                destOffset: framesFilled
            )
        }

        return noErr
    }

    nonisolated func fillBuffersWithSilence(
        buffers: UnsafeMutableAudioBufferListPointer,
        bufferCount: Int,
        targetFrames: Int,
        destOffset: Int = 0
    ) {
        let channelsToProcess = min(bufferCount, buffers.count)

        for ch in 0 ..< channelsToProcess {
            let destBuffer = buffers[ch]
            if let dest = destBuffer.mData?.assumingMemoryBound(to: Float.self) {
                memset(dest.advanced(by: destOffset), 0, targetFrames * MemoryLayout<Float>.size)
            }
        }
    }
}

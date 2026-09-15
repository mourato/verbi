@preconcurrency import AVFoundation
import CoreAudio
import Foundation

extension AudioRecorder {
    // MARK: - Source Node Configuration

    /// Creates an AVAudioSourceNode for system audio capture.
    /// - Parameters:
    ///   - queue: Thread-safe queue for audio buffers.
    ///   - partialState: Tracks partially consumed buffers between render cycles.
    /// - Returns: Configured AVAudioSourceNode ready for engine attachment.
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

    /// Validates callback inputs before processing audio data.
    /// - Parameters:
    ///   - frameCount: Number of frames requested.
    ///   - audioBufferList: Pointer to audio buffer list structure.
    /// - Returns: OSStatus error code; noErr if validation passes.
    nonisolated func validateCallbackInputs(
        frameCount: UInt32,
        audioBufferList: UnsafeMutablePointer<AudioBufferList>,
        queue: AudioBufferQueue,
        partialState: PartialBufferState
    ) -> OSStatus {
        guard frameCount > 0 else {
            return -50 // kAudio_ParamError
        }

        return processAudioBuffers(
            frameCount: frameCount,
            audioBufferList: audioBufferList,
            queue: queue,
            partialState: partialState
        )
    }

    /// Processes audio buffers by filling them with silence.
    /// - Parameters:
    ///   - frameCount: Number of frames to process.
    ///   - audioBufferList: Pointer to audio buffer list structure.
    /// - Returns: OSStatus indicating success (noErr) or failure.
    nonisolated func processAudioBuffers(
        frameCount: UInt32,
        audioBufferList: UnsafeMutablePointer<AudioBufferList>,
        queue: AudioBufferQueue,
        partialState: PartialBufferState
    ) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let targetFrames = Int(frameCount)
        var framesFilled = 0

        // 1. First, satisfy from partial state if something was left from previous cycle
        if partialState.hasPartial {
            framesFilled += partialState.consume(maxFrames: targetFrames, into: buffers, destOffset: 0)
        }

        // 2. Fill the rest from the queue
        while framesFilled < targetFrames {
            guard let nextBuffer = queue.dequeue() else {
                break // No more data: stop filling and return noErr (filled with silence)
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

            // If the buffer was only partially used, store it for next render cycle
            if copied < Int(nextBuffer.frameLength) {
                partialState.setBuffer(nextBuffer, offset: copied)
            } else {
                AudioPCMBufferLeaseRegistry.shared.releaseIfNeeded(for: nextBuffer)
            }
        }

        // 3. Zero out any remaining frames to avoid noise/clicks
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

    /// Fills audio buffers with silence (zeros).
    /// - Parameters:
    ///   - buffers: Pointer to mutable audio buffer list.
    ///   - bufferCount: Number of buffers to process.
    ///   - targetFrames: Number of frames to zero out.
    nonisolated func fillBuffersWithSilence(
        buffers: UnsafeMutableAudioBufferListPointer,
        bufferCount: Int,
        targetFrames: Int,
        destOffset: Int = 0
    ) {
        // Process up to the number of buffers requested or available, ensuring we don't go out of bounds
        let channelsToProcess = min(bufferCount, buffers.count)

        for ch in 0 ..< channelsToProcess {
            let destBuffer = buffers[ch]
            if let dest = destBuffer.mData?.assumingMemoryBound(to: Float.self) {
                memset(dest.advanced(by: destOffset), 0, targetFrames * MemoryLayout<Float>.size)
            }
        }
    }
}

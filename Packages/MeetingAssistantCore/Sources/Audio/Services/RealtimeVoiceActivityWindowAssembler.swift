@preconcurrency import AVFoundation
import Foundation
import os.lock

public actor RealtimeVoiceActivityWindowAssembler {
    public enum AdaptiveQualityMode: Sendable {
        case normal
        case reduced
    }

    public struct Window: Sendable {
        public let startTime: Double
        public let endTime: Double
        public let samples: [Float]

        public init(startTime: Double, endTime: Double, samples: [Float]) {
            self.startTime = startTime
            self.endTime = endTime
            self.samples = samples
        }
    }

    private struct AudioFormatSignature: Equatable {
        let sampleRate: Double
        let channelCount: AVAudioChannelCount
        let commonFormat: AVAudioCommonFormat
        let isInterleaved: Bool

        init(format: AVAudioFormat) {
            sampleRate = format.sampleRate
            channelCount = format.channelCount
            commonFormat = format.commonFormat
            isInterleaved = format.isInterleaved
        }
    }

    private struct ConverterCache {
        let sourceSignature: AudioFormatSignature
        let converter: AVAudioConverter
    }

    private struct Frame {
        let startSample: Int64
        let samples: [Float]
        let isVoice: Bool

        var endSample: Int64 {
            startSample + Int64(samples.count)
        }
    }

    private enum Constants {
        static let sampleRate = 16000.0
        static let sampleRateInt = 16000
        static let frameDurationSeconds = 0.03
        static let frameSampleCount = Int(Constants.sampleRate * Constants.frameDurationSeconds)
        static let speechThresholdDB: Float = -48
        static let speechStartFrameCount = 6
        static let speechEndFrameCount = 15
        static let preRollFrameCount = 7
        static let tailFrameCount = 8
        static let commitSpokenFrameCount = 400
        static let reducedModeVADDecimationFactor = 2
        static let remainderCompactionFrameThreshold = 12
    }

    private var absoluteSampleCursor: Int64 = 0
    private var sampleRemainder: [Float] = []
    private var sampleRemainderReadIndex = 0
    private var recentFrames: [Frame] = []
    private var activeFrames: [Frame] = []
    private var consecutiveVoiceFrames = 0
    private var consecutiveSilentFrames = 0
    private var activeSpeech = false
    private var spokenFramesInCurrentChunk = 0
    private var adaptiveQualityMode: AdaptiveQualityMode = .normal
    private var lastVoiceDecision = false
    private var voiceEvaluationFrameCounter = 0
    private lazy var targetFormat: AVAudioFormat? = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Constants.sampleRate,
        channels: 1,
        interleaved: false
    )
    private var converterCache: ConverterCache?
    private var convertedBufferScratch: AVAudioPCMBuffer?

    public init() {}

    public func setAdaptiveQualityMode(_ mode: AdaptiveQualityMode) {
        guard adaptiveQualityMode != mode else { return }
        adaptiveQualityMode = mode
        voiceEvaluationFrameCounter = 0
    }

    public func append(buffer: AVAudioPCMBuffer) throws -> [Window] {
        let convertedSamples = try convertTo16kHzMonoSamples(buffer: buffer)
        guard !convertedSamples.isEmpty else { return [] }

        sampleRemainder.append(contentsOf: convertedSamples)

        var emittedWindows: [Window] = []
        while remainingSampleCount >= Constants.frameSampleCount {
            let frameStart = sampleRemainderReadIndex
            let frameEnd = frameStart + Constants.frameSampleCount
            let frameSamples = Array(sampleRemainder[frameStart ..< frameEnd])
            sampleRemainderReadIndex = frameEnd

            let frame = Frame(
                startSample: absoluteSampleCursor,
                samples: frameSamples,
                isVoice: evaluateVoiceFrame(frameSamples)
            )
            absoluteSampleCursor += Int64(Constants.frameSampleCount)

            emittedWindows.append(contentsOf: process(frame: frame))
        }

        compactSampleRemainderIfNeeded()

        return emittedWindows
    }

    public func finish() throws -> [Window] {
        var emittedWindows: [Window] = []

        if remainingSampleCount > 0 {
            let remainingSamples = Array(sampleRemainder[sampleRemainderReadIndex...])
            let paddedSamples = remainingSamples + Array(
                repeating: 0,
                count: max(0, Constants.frameSampleCount - remainingSamples.count)
            )
            let frame = Frame(
                startSample: absoluteSampleCursor,
                samples: paddedSamples,
                isVoice: evaluateVoiceFrame(remainingSamples)
            )
            absoluteSampleCursor += Int64(Constants.frameSampleCount)
            emittedWindows.append(contentsOf: process(frame: frame))
            sampleRemainder.removeAll(keepingCapacity: true)
            sampleRemainderReadIndex = 0
        }

        if activeSpeech, let window = makeWindow(from: activeFrames, trimTrailingSilentFrames: 0) {
            emittedWindows.append(window)
        }

        resetState()
        return emittedWindows
    }

    private func process(frame: Frame) -> [Window] {
        recentFrames.append(frame)
        if recentFrames.count > Constants.preRollFrameCount {
            recentFrames.removeFirst(recentFrames.count - Constants.preRollFrameCount)
        }

        var emittedWindows: [Window] = []

        if activeSpeech {
            activeFrames.append(frame)

            if frame.isVoice {
                consecutiveSilentFrames = 0
                spokenFramesInCurrentChunk += 1
            } else {
                consecutiveSilentFrames += 1
            }

            if spokenFramesInCurrentChunk >= Constants.commitSpokenFrameCount,
               let window = makeWindow(from: activeFrames, trimTrailingSilentFrames: 0)
            {
                emittedWindows.append(window)
                activeFrames.removeAll(keepingCapacity: true)
                spokenFramesInCurrentChunk = 0
                consecutiveSilentFrames = 0
            } else if consecutiveSilentFrames >= Constants.speechEndFrameCount {
                let trimCount = max(0, consecutiveSilentFrames - Constants.tailFrameCount)
                if let window = makeWindow(from: activeFrames, trimTrailingSilentFrames: trimCount) {
                    emittedWindows.append(window)
                }
                activeSpeech = false
                activeFrames.removeAll(keepingCapacity: true)
                spokenFramesInCurrentChunk = 0
                consecutiveVoiceFrames = 0
                consecutiveSilentFrames = 0
            }

            return emittedWindows
        }

        if frame.isVoice {
            consecutiveVoiceFrames += 1
        } else {
            consecutiveVoiceFrames = 0
        }

        if consecutiveVoiceFrames >= Constants.speechStartFrameCount {
            activeSpeech = true
            activeFrames = recentFrames
            spokenFramesInCurrentChunk = activeFrames.reduce(into: 0) { partialResult, frame in
                if frame.isVoice {
                    partialResult += 1
                }
            }
            consecutiveSilentFrames = 0
        }

        return emittedWindows
    }

    private func makeWindow(from frames: [Frame], trimTrailingSilentFrames: Int) -> Window? {
        guard !frames.isEmpty else { return nil }

        let keepCount = max(0, frames.count - trimTrailingSilentFrames)
        let keptFrames = Array(frames.prefix(keepCount))
        guard !keptFrames.isEmpty else { return nil }

        let startSample = keptFrames[0].startSample
        let endSample = keptFrames[keptFrames.count - 1].endSample
        let samples = keptFrames.flatMap(\.samples)
        guard !samples.isEmpty else { return nil }

        return Window(
            startTime: Double(startSample) / Constants.sampleRate,
            endTime: Double(endSample) / Constants.sampleRate,
            samples: samples
        )
    }

    private func resetState() {
        absoluteSampleCursor = 0
        sampleRemainder.removeAll(keepingCapacity: true)
        sampleRemainderReadIndex = 0
        recentFrames.removeAll(keepingCapacity: false)
        activeFrames.removeAll(keepingCapacity: false)
        consecutiveVoiceFrames = 0
        consecutiveSilentFrames = 0
        activeSpeech = false
        spokenFramesInCurrentChunk = 0
        lastVoiceDecision = false
        voiceEvaluationFrameCounter = 0
        converterCache = nil
        convertedBufferScratch = nil
    }

    private func convertTo16kHzMonoSamples(buffer: AVAudioPCMBuffer) throws -> [Float] {
        guard let targetFormat else {
            throw RealtimeVoiceActivityError.conversionFailed
        }

        let workingBuffer: AVAudioPCMBuffer
        if buffer.format.sampleRate == Constants.sampleRate,
           buffer.format.channelCount == 1,
           buffer.format.commonFormat == .pcmFormatFloat32,
           !buffer.format.isInterleaved
        {
            workingBuffer = buffer
        } else {
            let converter = try converter(for: buffer.format, targetFormat: targetFormat)
            let convertedBuffer = try makeConvertedScratchBuffer(
                targetFormat: targetFormat,
                sourceFrameLength: buffer.frameLength,
                sourceSampleRate: buffer.format.sampleRate
            )
            try convert(buffer, with: converter, to: convertedBuffer)
            workingBuffer = convertedBuffer
        }

        guard let channelData = workingBuffer.floatChannelData else { return [] }
        let frameCount = Int(workingBuffer.frameLength)
        guard frameCount > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
    }

    private func converter(for sourceFormat: AVAudioFormat, targetFormat: AVAudioFormat) throws -> AVAudioConverter {
        let sourceSignature = AudioFormatSignature(format: sourceFormat)
        if let cached = converterCache, cached.sourceSignature == sourceSignature {
            return cached.converter
        }

        guard let createdConverter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw RealtimeVoiceActivityError.conversionFailed
        }
        converterCache = ConverterCache(sourceSignature: sourceSignature, converter: createdConverter)
        return createdConverter
    }

    private func makeConvertedScratchBuffer(
        targetFormat: AVAudioFormat,
        sourceFrameLength: AVAudioFrameCount,
        sourceSampleRate: Double
    ) throws -> AVAudioPCMBuffer {
        let targetFrameCapacity = AVAudioFrameCount(
            Double(sourceFrameLength) * Constants.sampleRate / sourceSampleRate
        ) + 1

        if let scratch = convertedBufferScratch,
           scratch.frameCapacity >= targetFrameCapacity
        {
            scratch.frameLength = 0
            return scratch
        }

        guard let allocatedBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: targetFrameCapacity
        ) else {
            throw RealtimeVoiceActivityError.conversionFailed
        }

        convertedBufferScratch = allocatedBuffer
        return allocatedBuffer
    }

    private func convert(
        _ inputBuffer: AVAudioPCMBuffer,
        with converter: AVAudioConverter,
        to outputBuffer: AVAudioPCMBuffer
    ) throws {
        guard converter.inputFormat.channelCount > 0 else {
            throw RealtimeVoiceActivityError.conversionFailed
        }

        var conversionError: NSError?
        let inputState = OSAllocatedUnfairLock(initialState: false)
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            let shouldProvideInput = inputState.withLock { hasProvidedInput in
                guard !hasProvidedInput else { return false }
                hasProvidedInput = true
                return true
            }

            guard shouldProvideInput else {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            return inputBuffer
        }

        _ = converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: inputBlock)
        if let conversionError {
            throw conversionError
        }
    }

    private var remainingSampleCount: Int {
        sampleRemainder.count - sampleRemainderReadIndex
    }

    private func compactSampleRemainderIfNeeded() {
        guard sampleRemainderReadIndex > 0 else { return }
        let threshold = Constants.frameSampleCount * Constants.remainderCompactionFrameThreshold
        let shouldCompact = sampleRemainderReadIndex >= threshold
            || sampleRemainderReadIndex * 2 >= sampleRemainder.count
            || remainingSampleCount == 0
        guard shouldCompact else { return }

        sampleRemainder.removeFirst(sampleRemainderReadIndex)
        sampleRemainderReadIndex = 0
    }

    private func evaluateVoiceFrame(_ samples: [Float]) -> Bool {
        switch adaptiveQualityMode {
        case .normal:
            voiceEvaluationFrameCounter = 0
            lastVoiceDecision = Self.isVoiceFrame(samples)
            return lastVoiceDecision
        case .reduced:
            if voiceEvaluationFrameCounter == 0 {
                lastVoiceDecision = Self.isVoiceFrame(samples)
            }
            voiceEvaluationFrameCounter = (voiceEvaluationFrameCounter + 1)
                % Constants.reducedModeVADDecimationFactor
            return lastVoiceDecision
        }
    }

    private static func isVoiceFrame(_ samples: [Float]) -> Bool {
        guard !samples.isEmpty else { return false }

        var sumSquares: Float = 0
        for sample in samples {
            sumSquares += sample * sample
        }

        let rms = sqrt(sumSquares / Float(samples.count))
        guard rms > 0 else { return false }
        let db = 20 * log10(rms)
        return db >= Constants.speechThresholdDB
    }
}

public enum RealtimeVoiceActivityError: Error {
    case conversionFailed
}

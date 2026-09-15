@preconcurrency import AVFoundation
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure
import os.log

public struct AudioCompactionResult: Sendable {
    public let outputURL: URL
    public let originalDuration: Double
    public let compactedDuration: Double
    public let removedDuration: Double
    public let removedRatio: Double
    public let wasCompacted: Bool

    public init(
        outputURL: URL,
        originalDuration: Double,
        compactedDuration: Double,
        removedDuration: Double,
        removedRatio: Double,
        wasCompacted: Bool
    ) {
        self.outputURL = outputURL
        self.originalDuration = originalDuration
        self.compactedDuration = compactedDuration
        self.removedDuration = removedDuration
        self.removedRatio = removedRatio
        self.wasCompacted = wasCompacted
    }
}

public protocol AudioSilenceCompacting: Sendable {
    func compactForTranscription(
        inputURL: URL,
        outputURL: URL,
        format: AppSettingsStore.AudioFormat
    ) async throws -> AudioCompactionResult
}

public final class AudioSilenceCompactor: AudioSilenceCompacting, @unchecked Sendable {
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "AudioSilenceCompactor")
    private let silenceAnalysisKernel: any SilenceAnalysisKernel

    private enum Constants {
        static let windowDurationSeconds = 0.03
        static let silenceThresholdDB: Double = -48
        static let minimumSilenceDurationSeconds = 0.9
        static let mergeGapDurationSeconds = 0.25
        static let paddingDurationSeconds = 0.12
        static let analysisChunkFrames: AVAudioFrameCount = 8192
    }

    public convenience init() {
        self.init(kernelProvider: .live)
    }

    public init(kernelProvider: AudioKernelProvider) {
        silenceAnalysisKernel = kernelProvider.makeSilenceAnalysisKernel()
    }

    init(silenceAnalysisKernel: any SilenceAnalysisKernel) {
        self.silenceAnalysisKernel = silenceAnalysisKernel
    }

    public func compactForTranscription(
        inputURL: URL,
        outputURL: URL,
        format: AppSettingsStore.AudioFormat
    ) async throws -> AudioCompactionResult {
        let silenceAnalysisKernel = silenceAnalysisKernel
        return try await Task.detached(priority: .userInitiated) {
            try await Self.compact(
                inputURL: inputURL,
                outputURL: outputURL,
                format: format,
                logger: self.logger,
                silenceAnalysisKernel: silenceAnalysisKernel
            )
        }
        .value
    }

    private static func compact(
        inputURL: URL,
        outputURL: URL,
        format: AppSettingsStore.AudioFormat,
        logger: Logger,
        silenceAnalysisKernel: any SilenceAnalysisKernel
    ) throws -> AudioCompactionResult {
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw AudioSilenceCompactorError.inputFileNotFound
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let analysis = try silenceAnalysisKernel.analyze(inputURL: inputURL)
        let originalDuration = analysis.durationSeconds

        guard !analysis.keepRanges.isEmpty else {
            return fallbackResult(for: inputURL, originalDuration: originalDuration)
        }

        let compactedDuration = analysis.keepRanges.reduce(0.0) { partial, range in
            partial + Double(range.count) / analysis.sampleRate
        }
        let removedDuration = max(0, originalDuration - compactedDuration)
        let removedRatio = originalDuration > 0 ? removedDuration / originalDuration : 0

        guard removedDuration > 0.05 else {
            return fallbackResult(for: inputURL, originalDuration: originalDuration)
        }

        try exportCompactedAsset(
            inputURL: inputURL,
            keepRanges: analysis.keepRanges,
            outputURL: outputURL,
            format: format
        )

        logger.info(
            "Audio silence compaction exported: input=\(inputURL.lastPathComponent, privacy: .public) output=\(outputURL.lastPathComponent, privacy: .public) removedDuration=\(removedDuration, privacy: .public) removedRatio=\(removedRatio, privacy: .public)"
        )

        return AudioCompactionResult(
            outputURL: outputURL,
            originalDuration: originalDuration,
            compactedDuration: compactedDuration,
            removedDuration: removedDuration,
            removedRatio: removedRatio,
            wasCompacted: true
        )
    }

    fileprivate static func analyzeAudio(inputURL: URL) throws -> AudioAnalysis {
        let audioFile = try AVAudioFile(forReading: inputURL)
        let sampleRate = audioFile.processingFormat.sampleRate
        let totalFrames = AVAudioFramePosition(audioFile.length)

        guard totalFrames > 0 else {
            return AudioAnalysis(sampleRate: sampleRate, totalFrames: 0, keepRanges: [])
        }

        let windows = try analyzeWindows(
            from: audioFile,
            sampleRate: sampleRate,
            totalFrames: totalFrames
        )
        let removableSilence = removableSilenceRanges(
            from: windows,
            minimumSilenceFrames: frames(for: Constants.minimumSilenceDurationSeconds, sampleRate: sampleRate)
        )
        let keepRanges = paddedKeepRanges(
            totalFrames: totalFrames,
            removableSilence: removableSilence,
            paddingFrames: frames(for: Constants.paddingDurationSeconds, sampleRate: sampleRate),
            mergeGapFrames: frames(for: Constants.mergeGapDurationSeconds, sampleRate: sampleRate)
        )

        return AudioAnalysis(
            sampleRate: sampleRate,
            totalFrames: totalFrames,
            keepRanges: keepRanges
        )
    }

    private static func analyzeWindows(
        from audioFile: AVAudioFile,
        sampleRate: Double,
        totalFrames: AVAudioFramePosition
    ) throws -> [SignalWindow] {
        let windowFrames = max(1, frames(for: Constants.windowDurationSeconds, sampleRate: sampleRate))
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: Constants.analysisChunkFrames
        ) else {
            throw AudioSilenceCompactorError.failedToAllocateBuffer
        }

        var windows: [SignalWindow] = []
        windows.reserveCapacity(Int(max(1, totalFrames / max(windowFrames, 1))))

        var currentFrame: AVAudioFramePosition = 0
        var windowStartFrame: AVAudioFramePosition = 0
        var accumulatedSquares = 0.0
        var accumulatedSamples = 0

        while currentFrame < totalFrames {
            try audioFile.read(into: buffer)

            let framesRead = Int(buffer.frameLength)
            if framesRead == 0 {
                break
            }

            let channelCount = Int(buffer.format.channelCount)
            guard channelCount > 0 else {
                throw AudioSilenceCompactorError.invalidChannelConfiguration
            }

            if let channelData = buffer.floatChannelData {
                for frameIndex in 0 ..< framesRead {
                    let monoSample = monoFloatSample(
                        channelData: channelData,
                        channelCount: channelCount,
                        frameIndex: frameIndex
                    )
                    accumulatedSquares += monoSample * monoSample
                    accumulatedSamples += 1
                    currentFrame += 1

                    if accumulatedSamples == windowFrames {
                        windows.append(
                            makeWindow(
                                startFrame: windowStartFrame,
                                endFrame: currentFrame,
                                accumulatedSquares: accumulatedSquares,
                                sampleCount: accumulatedSamples
                            )
                        )
                        windowStartFrame = currentFrame
                        accumulatedSquares = 0
                        accumulatedSamples = 0
                    }
                }
            } else if let channelData = buffer.int16ChannelData {
                for frameIndex in 0 ..< framesRead {
                    let monoSample = monoInt16Sample(
                        channelData: channelData,
                        channelCount: channelCount,
                        frameIndex: frameIndex
                    )
                    accumulatedSquares += monoSample * monoSample
                    accumulatedSamples += 1
                    currentFrame += 1

                    if accumulatedSamples == windowFrames {
                        windows.append(
                            makeWindow(
                                startFrame: windowStartFrame,
                                endFrame: currentFrame,
                                accumulatedSquares: accumulatedSquares,
                                sampleCount: accumulatedSamples
                            )
                        )
                        windowStartFrame = currentFrame
                        accumulatedSquares = 0
                        accumulatedSamples = 0
                    }
                }
            } else {
                throw AudioSilenceCompactorError.unsupportedPCMFormat
            }
        }

        if accumulatedSamples > 0 {
            windows.append(
                makeWindow(
                    startFrame: windowStartFrame,
                    endFrame: currentFrame,
                    accumulatedSquares: accumulatedSquares,
                    sampleCount: accumulatedSamples
                )
            )
        }

        return windows
    }

    private static func removableSilenceRanges(
        from windows: [SignalWindow],
        minimumSilenceFrames: AVAudioFramePosition
    ) -> [Range<AVAudioFramePosition>] {
        guard !windows.isEmpty else { return [] }

        var removableRanges: [Range<AVAudioFramePosition>] = []
        var activeSilenceStart: AVAudioFramePosition?

        for window in windows {
            if window.isSilent {
                activeSilenceStart = activeSilenceStart ?? window.startFrame
                continue
            }

            if let silenceStart = activeSilenceStart {
                let silenceRange = silenceStart ..< window.startFrame
                if AVAudioFramePosition(silenceRange.count) >= minimumSilenceFrames {
                    removableRanges.append(silenceRange)
                }
                activeSilenceStart = nil
            }
        }

        if let activeSilenceStart, let lastWindow = windows.last {
            let silenceRange = activeSilenceStart ..< lastWindow.endFrame
            if AVAudioFramePosition(silenceRange.count) >= minimumSilenceFrames {
                removableRanges.append(silenceRange)
            }
        }

        return removableRanges
    }

    private static func paddedKeepRanges(
        totalFrames: AVAudioFramePosition,
        removableSilence: [Range<AVAudioFramePosition>],
        paddingFrames: AVAudioFramePosition,
        mergeGapFrames: AVAudioFramePosition
    ) -> [Range<AVAudioFramePosition>] {
        guard totalFrames > 0 else { return [] }
        guard !removableSilence.isEmpty else { return [0 ..< totalFrames] }

        var keepRanges: [Range<AVAudioFramePosition>] = []
        var cursor: AVAudioFramePosition = 0

        for silenceRange in removableSilence {
            if cursor < silenceRange.lowerBound {
                keepRanges.append(cursor ..< silenceRange.lowerBound)
            }
            cursor = max(cursor, silenceRange.upperBound)
        }

        if cursor < totalFrames {
            keepRanges.append(cursor ..< totalFrames)
        }

        let paddedRanges = keepRanges.map { range in
            let start = max(0, range.lowerBound - paddingFrames)
            let end = min(totalFrames, range.upperBound + paddingFrames)
            return start ..< end
        }

        return mergeRanges(paddedRanges, mergeGapFrames: mergeGapFrames)
    }

    private static func mergeRanges(
        _ ranges: [Range<AVAudioFramePosition>],
        mergeGapFrames: AVAudioFramePosition
    ) -> [Range<AVAudioFramePosition>] {
        guard let first = ranges.first else { return [] }

        var merged: [Range<AVAudioFramePosition>] = [first]

        for range in ranges.dropFirst() {
            guard let last = merged.last else {
                merged.append(range)
                continue
            }

            let gap = range.lowerBound - last.upperBound
            if gap <= mergeGapFrames {
                merged[merged.count - 1] = last.lowerBound ..< max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }

        return merged
    }

    private static func exportCompactedAsset(
        inputURL: URL,
        keepRanges: [Range<AVAudioFramePosition>],
        outputURL: URL,
        format: AppSettingsStore.AudioFormat
    ) throws {
        let sourceFile = try AVAudioFile(forReading: inputURL)
        let sampleRate = sourceFile.processingFormat.sampleRate
        let channelCount = Int(sourceFile.processingFormat.channelCount)
        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: outputSettings(
                format: format,
                sampleRate: sampleRate,
                channelCount: channelCount
            ),
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: sourceFile.processingFormat,
            frameCapacity: Constants.analysisChunkFrames
        ) else {
            throw AudioSilenceCompactorError.failedToAllocateBuffer
        }

        for keepRange in keepRanges where !keepRange.isEmpty {
            sourceFile.framePosition = keepRange.lowerBound
            var remainingFrames = keepRange.count

            while remainingFrames > 0 {
                let framesToRead = min(Int(Constants.analysisChunkFrames), remainingFrames)
                buffer.frameLength = 0
                try sourceFile.read(into: buffer, frameCount: AVAudioFrameCount(framesToRead))

                guard buffer.frameLength > 0 else {
                    throw AudioSilenceCompactorError.failedToCreateExportSession
                }

                try outputFile.write(from: buffer)
                remainingFrames -= Int(buffer.frameLength)
            }
        }
    }

    private static func outputSettings(
        format: AppSettingsStore.AudioFormat,
        sampleRate: Double,
        channelCount: Int
    ) -> [String: Any] {
        switch format {
        case .m4a:
            [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount
            ]
        case .wav:
            [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: true
            ]
        }
    }

    private static func monoFloatSample(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount: Int,
        frameIndex: Int
    ) -> Double {
        var monoSample = 0.0
        for channelIndex in 0 ..< channelCount {
            monoSample += Double(channelData[channelIndex][frameIndex])
        }
        return monoSample / Double(channelCount)
    }

    private static func monoInt16Sample(
        channelData: UnsafePointer<UnsafeMutablePointer<Int16>>,
        channelCount: Int,
        frameIndex: Int
    ) -> Double {
        var monoSample = 0.0
        for channelIndex in 0 ..< channelCount {
            monoSample += Double(channelData[channelIndex][frameIndex]) / Double(Int16.max)
        }
        return monoSample / Double(channelCount)
    }

    private static func makeWindow(
        startFrame: AVAudioFramePosition,
        endFrame: AVAudioFramePosition,
        accumulatedSquares: Double,
        sampleCount: Int
    ) -> SignalWindow {
        let rms = sampleCount > 0 ? sqrt(accumulatedSquares / Double(sampleCount)) : 0
        let db = rms > 0 ? 20 * log10(rms) : -160

        return SignalWindow(
            startFrame: startFrame,
            endFrame: endFrame,
            isSilent: db <= Constants.silenceThresholdDB
        )
    }

    private static func frames(for durationSeconds: Double, sampleRate: Double) -> AVAudioFramePosition {
        AVAudioFramePosition((durationSeconds * sampleRate).rounded())
    }

    private static func fallbackResult(for inputURL: URL, originalDuration: Double) -> AudioCompactionResult {
        AudioCompactionResult(
            outputURL: inputURL,
            originalDuration: originalDuration,
            compactedDuration: originalDuration,
            removedDuration: 0,
            removedRatio: 0,
            wasCompacted: false
        )
    }
}

private struct AudioAnalysis {
    let sampleRate: Double
    let totalFrames: AVAudioFramePosition
    let keepRanges: [Range<AVAudioFramePosition>]

    var durationSeconds: Double {
        guard sampleRate > 0 else { return 0 }
        return Double(totalFrames) / sampleRate
    }
}

struct SwiftSilenceAnalysisKernel: SilenceAnalysisKernel {
    func analyze(inputURL: URL) throws -> AudioSilenceAnalysis {
        let analysis = try AudioSilenceCompactor.analyzeAudio(inputURL: inputURL)
        return AudioSilenceAnalysis(
            sampleRate: analysis.sampleRate,
            totalFrames: analysis.totalFrames,
            keepRanges: analysis.keepRanges
        )
    }
}

private struct SignalWindow {
    let startFrame: AVAudioFramePosition
    let endFrame: AVAudioFramePosition
    let isSilent: Bool
}

public enum AudioSilenceCompactorError: LocalizedError {
    case inputFileNotFound
    case failedToAllocateBuffer
    case invalidChannelConfiguration
    case unsupportedPCMFormat
    case failedToCreateExportSession
    case exportFailed(Error?)

    public var errorDescription: String? {
        switch self {
        case .inputFileNotFound:
            "Input audio file not found."
        case .failedToAllocateBuffer:
            "Failed to allocate the analysis buffer."
        case .invalidChannelConfiguration:
            "Input audio has an invalid channel configuration."
        case .unsupportedPCMFormat:
            "Input audio format is not supported for silence analysis."
        case .failedToCreateExportSession:
            "Failed to create the compacted audio export session."
        case let .exportFailed(error):
            if let error {
                "Compacted audio export failed: \(error.localizedDescription)"
            } else {
                "Compacted audio export failed."
            }
        }
    }
}

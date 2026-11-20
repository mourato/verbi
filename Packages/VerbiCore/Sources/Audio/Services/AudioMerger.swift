@preconcurrency import AVFoundation
import Foundation
import os.log
import VerbiCoreCommon
import VerbiCoreInfrastructure

@MainActor
public final class AudioMerger {
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "AudioMerger")

    public init() {}

    public func mergeAudioFiles(inputURLs: [URL], to outputURL: URL, format: AppSettingsStore.AudioFormat) async throws -> URL {
        let existingURLs = inputURLs.filter { FileManager.default.fileExists(atPath: $0.path) }

        guard !existingURLs.isEmpty else {
            throw AudioMergerError.noInputFiles
        }

        if existingURLs.count == 1 {
            let sourceURL = existingURLs[0]
            if sourceURL == outputURL {
                logger.info("Single input file already at destination. Skipping merge.")
                return outputURL
            }

            if sourceURL.pathExtension == outputURL.pathExtension {
                logger.info("Moving single input file to destination: \(outputURL.path)")
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                }
                try FileManager.default.moveItem(at: sourceURL, to: outputURL)
                return outputURL
            }
        }

        logger.info("Merging \(existingURLs.count) audio files to: \(outputURL.path) (Format: \(format.displayName))")

        if FileManager.default.fileExists(atPath: outputURL.path), !existingURLs.contains(outputURL) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let composition = AVMutableComposition()

        try await buildComposition(composition, from: existingURLs)

        let sampleRate = await extractSampleRate(from: composition) ?? 48000.0
        logger.info("Using sample rate: \(sampleRate)Hz for export")

        try await export(composition: composition, to: outputURL, format: format, sampleRate: sampleRate)

        return outputURL
    }

    private func buildComposition(_ composition: AVMutableComposition, from urls: [URL]) async throws {
        for (index, url) in urls.enumerated() {
            let asset = AVURLAsset(url: url)
            do {
                let tracks = try await asset.loadTracks(withMediaType: .audio)
                let duration = try await asset.load(.duration)

                guard let track = tracks.first, let compositionTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: Int32(index + 1)
                ) else { continue }

                try compositionTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: track,
                    at: .zero
                )
            } catch {
                logger.warning("Failed to add track from \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    private func extractSampleRate(from asset: AVAsset) async -> Double? {
        do {
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard let track = tracks.first else { return nil }
            let formatDescriptions = try await track.load(.formatDescriptions)
            guard let formatDesc = formatDescriptions.first else { return nil }

            let audioDesc = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
            return audioDesc?.pointee.mSampleRate
        } catch {
            logger.warning("Failed to extract sample rate: \(error.localizedDescription)")
            return nil
        }
    }

    private func export(
        composition: AVAsset,
        to outputURL: URL,
        format: AppSettingsStore.AudioFormat,
        sampleRate: Double
    ) async throws {
        let (reader, readerOutput) = try await createReader(for: composition)
        let (writer, writerInput) = try createWriter(outputURL: outputURL, format: format, sampleRate: sampleRate)

        if !reader.startReading() {
            throw AudioMergerError.exportFailed(reader.error)
        }
        if !writer.startWriting() {
            throw AudioMergerError.exportFailed(writer.error)
        }

        writer.startSession(atSourceTime: .zero)

        let context = ExportContext(reader: reader, output: readerOutput, input: writerInput)

        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "audioMerger.export")

            writerInput.requestMediaDataWhenReady(on: queue) {
                processExportLoop(context: context, continuation: continuation)
            }
        }

        await writer.finishWriting()

        if writer.status == .failed {
            throw AudioMergerError.exportFailed(writer.error)
        }
        if reader.status == .failed {
            throw AudioMergerError.exportFailed(reader.error)
        }
    }

    private func createReader(for composition: AVAsset) async throws -> (AVAssetReader, AVAssetReaderOutput) {
        let reader = try AVAssetReader(asset: composition)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false
        ]

        let tracks = try await composition.loadTracks(withMediaType: .audio)

        guard !tracks.isEmpty else {
            throw AudioMergerError.noValidTracks
        }

        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: settings)

        guard reader.canAdd(output) else {
            throw AudioMergerError.failedToCreateExportSession
        }
        reader.add(output)

        return (reader, output)
    }

    private func createWriter(
        outputURL: URL,
        format: AppSettingsStore.AudioFormat,
        sampleRate: Double
    ) throws -> (AVAssetWriter, AVAssetWriterInput) {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: format == .m4a ? .m4a : .wav)
        let settings = getWriterSettings(for: format, sampleRate: sampleRate)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)

        input.expectsMediaDataInRealTime = false

        guard writer.canAdd(input) else {
            throw AudioMergerError.failedToCreateExportSession
        }
        writer.add(input)

        return (writer, input)
    }

    private func getWriterSettings(for format: AppSettingsStore.AudioFormat, sampleRate: Double) -> [String: Any] {
        switch format {
        case .m4a:
            [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: sampleRate,
                AVEncoderBitRateKey: 128_000
            ]
        case .wav:
            [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: sampleRate,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        }
    }
}

private struct ExportContext: @unchecked Sendable {
    let reader: AVAssetReader
    let output: AVAssetReaderOutput
    let input: AVAssetWriterInput
}

private func processExportLoop(context: ExportContext, continuation: CheckedContinuation<Void, Never>) {
    let input = context.input
    let output = context.output
    let reader = context.reader

    while input.isReadyForMoreMediaData {
        if let buffer = output.copyNextSampleBuffer() {
            if !input.append(buffer) {
                input.markAsFinished()
                continuation.resume()
                return
            }
        } else {
            if reader.status == .failed {
                input.markAsFinished()
            } else {
                input.markAsFinished()
            }
            continuation.resume()
            return
        }
    }
}

public enum AudioMergerError: LocalizedError {
    case noInputFiles
    case noValidTracks
    case failedToCreateExportSession
    case exportFailed(Error?)
    case exportCancelled

    public var errorDescription: String? {
        switch self {
        case .noInputFiles:
            return "No input files provided for merging"
        case .noValidTracks:
            return "No valid audio tracks found in input files"
        case .failedToCreateExportSession:
            return "Failed to create audio export session"
        case let .exportFailed(error):
            if let error {
                return "Audio export failed: \(error.localizedDescription)"
            }
            return "Audio export failed"
        case .exportCancelled:
            return "Audio export was cancelled"
        }
    }
}

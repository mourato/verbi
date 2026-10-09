@preconcurrency import AVFoundation
import Combine
@preconcurrency import FluidAudio
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure
import os.log

extension FluidAIModelManager {
    /// Structure to hold raw diarization result
    struct DiarizationSegment: Identifiable {
        let id = UUID()
        let speakerId: String
        let startTime: Double
        let endTime: Double
    }

    /// Perform speaker diarization on an audio file
    func diarize(
        audioURL: URL,
        minSpeakers: Int? = nil,
        maxSpeakers: Int? = nil,
        numSpeakers: Int? = nil
    ) async throws -> [DiarizationSegment] {
        lastDiarizationActivityAt = Date()
        diarizationInFlightOperationCount += 1
        defer { diarizationInFlightOperationCount = max(0, diarizationInFlightOperationCount - 1) }

        await loadDiarizationModels(
            minSpeakers: minSpeakers,
            maxSpeakers: maxSpeakers,
            numSpeakers: numSpeakers
        )

        guard let manager = diarizerManager else {
            throw FluidError.diarizerNotLoaded
        }

        logger.info("Diarizing audio file: \(audioURL.path)")

        let result = try await manager.process(audioURL)

        return result.segments.map { segment in
            DiarizationSegment(
                speakerId: String(segment.speakerId),
                startTime: Double(segment.startTimeSeconds),
                endTime: Double(segment.endTimeSeconds)
            )
        }
    }

    /// Structure to hold ASR segment (text + timing)
    struct AsrSegment {
        let text: String
        let startTime: Double
        let endTime: Double
    }

    struct AsrTranscriptionOutput {
        let text: String
        let segments: [AsrSegment]
        let confidenceScore: Double?
    }

    /// Transcribe audio from a URL.
    func transcribe(
        audioURL: URL,
        inputLanguageHintCode: String? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> AsrTranscriptionOutput {
        recordASRActivity()
        guard modelState == .loaded, let loadedASRLocalModelID else {
            throw FluidError.modelNotLoaded
        }
        let loadedModel = resolveLocalModel(from: loadedASRLocalModelID)

        asrInFlightOperationCount += 1
        defer { asrInFlightOperationCount = max(0, asrInFlightOperationCount - 1) }

        logger.info("Transcribing audio file: \(audioURL.path)")

        switch loadedModel {
        case .parakeetTdt06BV3:
            if let inputLanguageHintCode, !inputLanguageHintCode.isEmpty {
                logger.info(
                    "ASR language hint requested: \(inputLanguageHintCode) (FluidAudio currently auto-detects language)"
                )
            }

            guard let manager = asrManager else {
                throw FluidError.modelNotLoaded
            }

            let stream = await manager.transcriptionProgressStream
            let progressTask = Task {
                if let progress {
                    do {
                        for try await fraction in stream {
                            progress(fraction * 100.0)
                        }
                    } catch {
                        // Keep transcription resilient when progress stream fails.
                    }
                }
            }
            defer { progressTask.cancel() }

            // Independent files and cumulative previews must not inherit decoder state.
            var decoderState = try await TdtDecoderState(decoderLayers: manager.decoderLayerCount)
            let result = try await manager.transcribe(audioURL, decoderState: &decoderState)

            let mappedSegments = (result.tokenTimings ?? []).map { timing in
                AsrSegment(
                    text: timing.token,
                    startTime: Double(timing.startTime),
                    endTime: Double(timing.endTime)
                )
            }

            return AsrTranscriptionOutput(
                text: result.text,
                segments: mappedSegments,
                confidenceScore: Double(result.confidence)
            )
        }
    }

    func transcribe(
        samples: [Float],
        inputLanguageHintCode: String? = nil
    ) async throws -> AsrTranscriptionOutput {
        recordASRActivity()
        guard modelState == .loaded, let loadedASRLocalModelID else {
            throw FluidError.modelNotLoaded
        }
        let loadedModel = resolveLocalModel(from: loadedASRLocalModelID)

        asrInFlightOperationCount += 1
        defer { asrInFlightOperationCount = max(0, asrInFlightOperationCount - 1) }

        logger.info("Transcribing in-memory audio samples: \(samples.count)")

        switch loadedModel {
        case .parakeetTdt06BV3:
            if let inputLanguageHintCode, !inputLanguageHintCode.isEmpty {
                logger.info(
                    "ASR language hint requested: \(inputLanguageHintCode) (FluidAudio currently auto-detects language)"
                )
            }

            guard let manager = asrManager else {
                throw FluidError.modelNotLoaded
            }

            // Each preview reprocesses its samples from the start.
            var decoderState = try await TdtDecoderState(decoderLayers: manager.decoderLayerCount)
            let result = try await manager.transcribe(samples, decoderState: &decoderState)

            let mappedSegments = (result.tokenTimings ?? []).map { timing in
                AsrSegment(
                    text: timing.token,
                    startTime: Double(timing.startTime),
                    endTime: Double(timing.endTime)
                )
            }

            return AsrTranscriptionOutput(
                text: result.text,
                segments: mappedSegments,
                confidenceScore: Double(result.confidence)
            )
        }
    }

    private func convertTo16kHz(buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false
            )
        else {
            throw FluidError.conversionFailed
        }

        if buffer.format.sampleRate == 16000, buffer.format.channelCount == 1 {
            return buffer
        }

        guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
            throw FluidError.conversionFailed
        }

        let targetFrameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate
        )

        guard
            let targetBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat, frameCapacity: targetFrameCapacity
            )
        else {
            throw FluidError.conversionFailed
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: targetBuffer, error: &error, withInputFrom: inputBlock)

        if let error {
            throw error
        }

        return targetBuffer
    }

    private func arrayFloat(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let channelPointer = channelData[0]
        return Array(UnsafeBufferPointer(start: channelPointer, count: Int(buffer.frameLength)))
    }
}

enum FluidError: LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(String)
    case diarizerNotLoaded
    case audioReadFailed
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case let .modelLoadFailed(reason):
            "Local ASR model failed to load: \(reason)"
        case .modelNotLoaded, .diarizerNotLoaded, .audioReadFailed, .conversionFailed:
            nil
        }
    }
}

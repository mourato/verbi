import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import os.log

/// Client for local transcription using FluidAudio.
@MainActor
public class LocalTranscriptionClient {
    public static let shared = LocalTranscriptionClient()

    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "LocalTranscriptionClient")
    private let manager = FluidAIModelManager.shared

    private struct TranscriptionRunContext {
        let text: String
        let asrSegments: [FluidAIModelManager.AsrSegment]
        let audioURL: URL
        let minSpeakers: Int?
        let maxSpeakers: Int?
        let numSpeakers: Int?
    }

    private init() {}

    /// Initializes and warms up the model.
    public func prepare() async {
        await manager.loadModels()
    }

    /// Transcribe an audio file locally.
    /// - Parameter audioURL: Path to the audio file.
    /// - Parameter onProgress: Optional callback for transcription progress.
    /// - Returns: TranscriptionResponse compatible with existing app logic.
    public func transcribe(
        audioURL: URL,
        isDiarizationEnabled: Bool? = nil,
        modelID: String = MeetingAssistantCoreInfrastructure.TranscriptionProvider.localModelID,
        inputLanguageHintCode: String? = nil,
        minSpeakers: Int? = nil,
        maxSpeakers: Int? = nil,
        numSpeakers: Int? = nil,
        useSettingsLanguageFallback: Bool = true,
        useSettingsDiarizationFallback: Bool = true,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> TranscriptionResponse {
        logger.info("Starting local transcription for: \(audioURL.lastPathComponent)")
        let selectedModel = LocalTranscriptionModel(rawValue: modelID) ?? .parakeetTdt06BV3

        await ensureASRModelLoaded(for: selectedModel)

        let startTime = Date()
        let resolvedLanguageCode = normalizedLanguageCode(
            inputLanguageHintCode,
            fallbackHint: useSettingsLanguageFallback ? AppSettingsStore.shared.transcriptionInputLanguageHint.languageCode : nil
        )

        let asrOutput = try await manager.transcribe(
            audioURL: audioURL,
            inputLanguageHintCode: resolvedLanguageCode,
            progress: onProgress
        )

        let context = TranscriptionRunContext(
            text: asrOutput.text,
            asrSegments: asrOutput.segments,
            audioURL: audioURL,
            minSpeakers: minSpeakers,
            maxSpeakers: maxSpeakers,
            numSpeakers: numSpeakers
        )

        let segments = await resolveSegmentsWithOptionalDiarization(
            context: context,
            isDiarizationEnabled: isDiarizationEnabled,
            model: selectedModel,
            useSettingsFallback: useSettingsDiarizationFallback
        )

        let duration = Date().timeIntervalSince(startTime)
        let processedAt = ISO8601DateFormatter().string(from: Date())

        return TranscriptionResponse(
            text: asrOutput.text,
            segments: segments,
            language: resolvedLanguageCode ?? "auto",
            durationSeconds: duration,
            model: selectedModel.rawValue,
            processedAt: processedAt,
            confidenceScore: asrOutput.confidenceScore
        )
    }

    public func transcribe(
        samples: [Float],
        inputLanguageHintCode: String? = nil,
        modelID: String = MeetingAssistantCoreInfrastructure.TranscriptionProvider.localModelID,
        useSettingsLanguageFallback: Bool = true
    ) async throws -> TranscriptionResponse {
        logger.info("Starting local in-memory transcription for \(samples.count) samples")

        let selectedModel = LocalTranscriptionModel(rawValue: modelID) ?? .parakeetTdt06BV3

        await ensureASRModelLoaded(for: selectedModel)

        let startTime = Date()
        let resolvedLanguageCode = normalizedLanguageCode(
            inputLanguageHintCode,
            fallbackHint: useSettingsLanguageFallback ? AppSettingsStore.shared.transcriptionInputLanguageHint.languageCode : nil
        )
        let asrOutput = try await manager.transcribe(
            samples: samples,
            inputLanguageHintCode: resolvedLanguageCode
        )
        let duration = Date().timeIntervalSince(startTime)
        let processedAt = ISO8601DateFormatter().string(from: Date())

        let segments = asrOutput.segments.map { segment in
            Transcription.Segment(
                speaker: Transcription.unknownSpeaker,
                text: segment.text,
                startTime: segment.startTime,
                endTime: segment.endTime
            )
        }

        return TranscriptionResponse(
            text: asrOutput.text,
            segments: segments,
            language: resolvedLanguageCode ?? "auto",
            durationSeconds: duration,
            model: selectedModel.rawValue,
            processedAt: processedAt,
            confidenceScore: asrOutput.confidenceScore
        )
    }

    private func ensureASRModelLoaded(for selectedModel: LocalTranscriptionModel) async {
        let isExpectedModelLoaded = manager.modelState == .loaded
            && manager.loadedASRLocalModelID == selectedModel.rawValue

        if !isExpectedModelLoaded {
            await manager.loadModels(for: selectedModel.rawValue)
        }
    }

    private func normalizedLanguageCode(_ requestedCode: String?, fallbackHint: String?) -> String? {
        let candidates = [requestedCode, fallbackHint]
        for candidate in candidates {
            let normalized = candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let normalized, !normalized.isEmpty {
                return normalized
            }
        }
        return nil
    }

    private func resolveSegmentsWithOptionalDiarization(
        context: TranscriptionRunContext,
        isDiarizationEnabled: Bool?,
        model: LocalTranscriptionModel,
        useSettingsFallback: Bool = true
    ) async -> [Transcription.Segment] {
        let diarizationSetting = isDiarizationEnabled ?? (useSettingsFallback && AppSettingsStore.shared.isDiarizationEnabled)
        let diarizationEnabled = diarizationSetting && FeatureFlags.enableDiarization && model.supportsDiarization

        if diarizationSetting, !model.supportsDiarization {
            logger.info("Diarization auto-disabled for local model: \(model.rawValue)")
        }

        guard diarizationEnabled else {
            logger.info(
                "Diarization disabled for this run (setting=\(diarizationSetting, privacy: .public), flag=\(FeatureFlags.enableDiarization, privacy: .public))."
            )
            return []
        }

        return await diarizedSegments(
            context: context
        )
    }

    private func diarizedSegments(
        context: TranscriptionRunContext
    ) async -> [Transcription.Segment] {
        logger.info("Diarization enabled. Processing with automatic speaker count...")

        do {
            let diarizationSegments = try await manager.diarize(
                audioURL: context.audioURL,
                minSpeakers: context.minSpeakers,
                maxSpeakers: context.maxSpeakers,
                numSpeakers: context.numSpeakers
            )
            logger.info("Diarization produced \(diarizationSegments.count) segments")

            if context.asrSegments.isEmpty {
                logger.info("ASR segments unavailable. Falling back to diarization-only segmentation.")
                return fallbackSegments(text: context.text, speakers: diarizationSegments)
            }

            let merged = merge(
                text: context.text,
                asrSegments: context.asrSegments,
                speakers: diarizationSegments
            )
            if merged.isEmpty {
                logger.info("Merged segments empty. Falling back to diarization-only segmentation.")
                return fallbackSegments(text: context.text, speakers: diarizationSegments)
            }
            return merged
        } catch {
            logger.error("Diarization failed: \(error.localizedDescription). Proceeding with transcription only.")
            return []
        }
    }

    public func diarize(audioURL: URL) async throws -> [SpeakerTimelineSegment] {
        let diarizationSegments = try await manager.diarize(audioURL: audioURL)
        return diarizationSegments.map { segment in
            SpeakerTimelineSegment(
                speaker: segment.speakerId,
                startTime: segment.startTime,
                endTime: segment.endTime
            )
        }
    }

    public func assignSpeakers(
        to segments: [Transcription.Segment],
        using speakerTimeline: [SpeakerTimelineSegment]
    ) -> [Transcription.Segment] {
        guard !segments.isEmpty, !speakerTimeline.isEmpty else { return segments }

        var result: [Transcription.Segment] = []
        var currentSpeaker = ""
        var currentBatch: [Transcription.Segment] = []

        for segment in segments {
            let midPoint = (segment.startTime + segment.endTime) / 2.0
            let speaker = speakerTimeline.first {
                $0.startTime <= midPoint && $0.endTime >= midPoint
            }?.speaker ?? Transcription.unknownSpeaker

            if speaker != currentSpeaker {
                if let mergedSegment = makeAssignedSegment(from: currentBatch, speaker: currentSpeaker) {
                    result.append(mergedSegment)
                }
                currentSpeaker = speaker
                currentBatch = []
            }

            currentBatch.append(segment)
        }

        if let mergedSegment = makeAssignedSegment(from: currentBatch, speaker: currentSpeaker) {
            result.append(mergedSegment)
        }

        return result.isEmpty ? segments : result
    }

    /// Merges ASR segments with Speaker segments to produce aligned transcription segments.
    private func merge(
        text _: String,
        asrSegments: [FluidAIModelManager.AsrSegment],
        speakers: [FluidAIModelManager.DiarizationSegment]
    ) -> [Transcription.Segment] {
        guard !asrSegments.isEmpty, !speakers.isEmpty else { return [] }

        let transcriptionSegments = asrSegments.map { segment in
            Transcription.Segment(
                speaker: Transcription.unknownSpeaker,
                text: segment.text,
                startTime: segment.startTime,
                endTime: segment.endTime
            )
        }

        let speakerTimeline = speakers.map { segment in
            SpeakerTimelineSegment(
                speaker: segment.speakerId,
                startTime: segment.startTime,
                endTime: segment.endTime
            )
        }

        return assignSpeakers(to: transcriptionSegments, using: speakerTimeline)
    }

    private func fallbackSegments(
        text: String,
        speakers: [FluidAIModelManager.DiarizationSegment]
    ) -> [Transcription.Segment] {
        let sortedSpeakers = speakers.sorted { $0.startTime < $1.startTime }
        let words = text.split(whereSeparator: \.isWhitespace)
        guard !sortedSpeakers.isEmpty, !words.isEmpty else { return [] }

        let totalDuration = sortedSpeakers.reduce(0.0) { partial, segment in
            partial + max(0, segment.endTime - segment.startTime)
        }

        var result: [Transcription.Segment] = []
        var currentIndex = 0
        var remainingDuration = totalDuration

        for (index, speaker) in sortedSpeakers.enumerated() {
            let remainingWords = words.count - currentIndex
            guard remainingWords > 0 else { break }

            let duration = max(0, speaker.endTime - speaker.startTime)
            let isLast = index == sortedSpeakers.count - 1

            let wordCount: Int
            if isLast {
                wordCount = remainingWords
            } else if remainingDuration > 0 {
                let ratio = duration / remainingDuration
                wordCount = max(1, Int(round(ratio * Double(remainingWords))))
            } else {
                wordCount = max(1, remainingWords / max(1, sortedSpeakers.count - index))
            }

            let endIndex = min(currentIndex + wordCount, words.count)
            let segmentText = words[currentIndex ..< endIndex].joined(separator: " ").trimmingCharacters(in: .whitespaces)
            currentIndex = endIndex
            remainingDuration -= duration

            guard !segmentText.isEmpty else { continue }

            result.append(
                Transcription.Segment(
                    speaker: speaker.speakerId,
                    text: segmentText,
                    startTime: speaker.startTime,
                    endTime: speaker.endTime
                )
            )
        }

        if currentIndex < words.count, !result.isEmpty {
            let remainder = words[currentIndex...].joined(separator: " ")
            let last = result[result.count - 1]
            let updated = Transcription.Segment(
                id: last.id,
                speaker: last.speaker,
                text: "\(last.text) \(remainder)".trimmingCharacters(in: .whitespaces),
                startTime: last.startTime,
                endTime: last.endTime
            )
            result[result.count - 1] = updated
        }

        return result
    }

    private func makeAssignedSegment(
        from batch: [Transcription.Segment],
        speaker: String
    ) -> Transcription.Segment? {
        guard !batch.isEmpty else { return nil }

        let segmentText = batch
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !segmentText.isEmpty else { return nil }

        return Transcription.Segment(
            speaker: speaker.isEmpty ? Transcription.unknownSpeaker : speaker,
            text: segmentText,
            startTime: batch.first?.startTime ?? 0,
            endTime: batch.last?.endTime ?? 0
        )
    }
}

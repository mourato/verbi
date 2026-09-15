// TranscriptionRepositoryAdapter - Adapter para TranscriptionRepository usando TranscriptionClient

import Foundation
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

/// Adapter que implementa TranscriptionRepository usando TranscriptionClient existente
@MainActor
public final class TranscriptionRepositoryAdapter: TranscriptionRepository, TranscriptionRepositoryDiarizationOverride, TranscriptionRepositoryPurposeAware, TranscriptionRepositoryPurposeDiarized, TranscriptionRepositoryFinalDiarization {
    private let transcriptionService: any TranscriptionService

    public init(transcriptionService: any TranscriptionService) {
        self.transcriptionService = transcriptionService
    }

    public func healthCheck() async throws -> Bool {
        try await transcriptionService.healthCheck()
    }

    public func fetchServiceStatus() async throws -> DomainServiceStatusResponse {
        let status = try await transcriptionService.fetchServiceStatus()
        return DomainServiceStatusResponse(
            status: status.status,
            message: "Model: \(status.modelName), State: \(status.modelState)",
            timestamp: Date()
        )
    }

    public func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> DomainTranscriptionResponse {
        try await transcribe(
            audioURL: audioURL,
            onProgress: onProgress,
            diarizationEnabledOverride: nil,
            capturePurpose: .meeting
        )
    }

    public func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        capturePurpose: CapturePurpose
    ) async throws -> DomainTranscriptionResponse {
        try await transcribe(
            audioURL: audioURL,
            onProgress: onProgress,
            diarizationEnabledOverride: nil,
            capturePurpose: capturePurpose
        )
    }

    public func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        diarizationEnabledOverride: Bool?
    ) async throws -> DomainTranscriptionResponse {
        try await transcribe(
            audioURL: audioURL,
            onProgress: onProgress,
            diarizationEnabledOverride: diarizationEnabledOverride,
            capturePurpose: .meeting
        )
    }

    public func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        diarizationEnabledOverride: Bool?,
        capturePurpose: CapturePurpose
    ) async throws -> DomainTranscriptionResponse {
        let response: TranscriptionResponse = if let purposeAwareService = transcriptionService as? any TranscriptionServicePurposeDiarized {
            try await purposeAwareService.transcribe(
                audioURL: audioURL,
                onProgress: onProgress,
                diarizationEnabledOverride: diarizationEnabledOverride,
                capturePurpose: capturePurpose
            )
        } else if let purposeAwareService = transcriptionService as? any TranscriptionServicePurposeAware,
                  diarizationEnabledOverride == nil
        {
            try await purposeAwareService.transcribe(
                audioURL: audioURL,
                onProgress: onProgress,
                capturePurpose: capturePurpose
            )
        } else if let diarizationAwareService = transcriptionService as? any TranscriptionServiceDiarizationOverride {
            try await diarizationAwareService.transcribe(
                audioURL: audioURL,
                onProgress: onProgress,
                diarizationEnabledOverride: diarizationEnabledOverride
            )
        } else {
            try await transcriptionService.transcribe(
                audioURL: audioURL,
                onProgress: onProgress
            )
        }

        return mapToDomainResponse(response)
    }

    public func transcribe(
        samples: [Float]
    ) async throws -> DomainTranscriptionResponse {
        let response = try await transcriptionService.transcribe(samples: samples)
        return mapToDomainResponse(response)
    }

    public func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        configuration: DomainTranscriptionRequestConfiguration,
        diarizationEnabledOverride: Bool?,
        capturePurpose: CapturePurpose
    ) async throws -> DomainTranscriptionResponse {
        guard TranscriptionProvider(rawValue: configuration.providerID) != nil else {
            throw TranscriptionError.transcriptionFailed("Unsupported transcription provider")
        }
        let response = try await transcriptionService.transcribe(
            audioURL: audioURL,
            onProgress: onProgress,
            executionMode: capturePurpose.transcriptionExecutionMode,
            diarizationEnabledOverride: diarizationEnabledOverride,
            configuration: configuration
        )
        return mapToDomainResponse(response)
    }

    public func transcribe(
        samples: [Float],
        configuration: DomainTranscriptionRequestConfiguration
    ) async throws -> DomainTranscriptionResponse {
        guard TranscriptionProvider(rawValue: configuration.providerID) != nil else {
            throw TranscriptionError.transcriptionFailed("Unsupported transcription provider")
        }
        let response = try await transcriptionService.transcribe(
            samples: samples,
            configuration: configuration
        )
        return mapToDomainResponse(response)
    }

    public func diarize(audioURL: URL) async throws -> [SpeakerTimelineSegment] {
        guard let diarizationService = transcriptionService as? any TranscriptionServiceFinalDiarization else {
            throw TranscriptionError.transcriptionFailed("Final diarization unsupported in current backend")
        }
        return try await diarizationService.diarize(audioURL: audioURL)
    }

    public func assignSpeakers(
        to segments: [DomainTranscriptionSegment],
        using speakerTimeline: [SpeakerTimelineSegment]
    ) -> [DomainTranscriptionSegment] {
        guard let diarizationService = transcriptionService as? any TranscriptionServiceFinalDiarization else {
            return segments
        }

        let mappedSegments = segments.map { segment in
            Transcription.Segment(
                id: segment.id,
                speaker: segment.speaker,
                text: segment.text,
                startTime: segment.startTime,
                endTime: segment.endTime
            )
        }

        return diarizationService.assignSpeakers(
            to: mappedSegments,
            using: speakerTimeline
        ).map { segment in
            DomainTranscriptionSegment(
                id: segment.id,
                speaker: segment.speaker,
                text: segment.text,
                startTime: segment.startTime,
                endTime: segment.endTime
            )
        }
    }

    private func mapToDomainResponse(_ response: TranscriptionResponse) -> DomainTranscriptionResponse {
        DomainTranscriptionResponse(
            text: response.text,
            segments: response.segments.map { segment in
                DomainTranscriptionSegment(
                    speaker: segment.speaker,
                    text: segment.text,
                    startTime: segment.startTime,
                    endTime: segment.endTime
                )
            },
            language: response.language,
            durationSeconds: response.durationSeconds,
            model: response.model,
            processedAt: response.processedAt,
            confidenceScore: response.confidenceScore
        )
    }
}

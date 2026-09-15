import Foundation
import MeetingAssistantCoreDomain

extension FileSystemStorageService {
    // MARK: - Core Data helpers

    static func convertToEntity(_ transcription: Transcription) -> TranscriptionEntity {
        let meeting = transcription.meeting.sanitizedForPersistence()
        let meetingEntity = MeetingEntity(
            id: meeting.id,
            app: DomainMeetingApp(rawValue: meeting.app.rawValue) ?? .unknown,
            capturePurpose: meeting.capturePurpose,
            appBundleIdentifier: meeting.appBundleIdentifier,
            appDisplayName: meeting.appDisplayName,
            title: meeting.title,
            linkedCalendarEvent: meeting.linkedCalendarEvent,
            startTime: meeting.startTime,
            endTime: meeting.endTime,
            audioFilePath: meeting.audioFilePath
        )

        let segments = transcription.segments.map { segment in
            TranscriptionEntity.Segment(
                id: segment.id,
                speaker: segment.speaker,
                text: segment.text,
                startTime: segment.startTime,
                endTime: segment.endTime
            )
        }

        var config = TranscriptionEntity.Configuration(
            text: transcription.text,
            rawText: transcription.rawText,
            segments: segments,
            language: transcription.language
        )
        config.id = transcription.id
        config.contextItems = transcription.contextItems
        config.processedContent = transcription.processedContent
        config.canonicalSummary = transcription.canonicalSummary
        config.qualityProfile = transcription.qualityProfile
        config.postProcessingPromptId = transcription.postProcessingPromptId
        config.postProcessingPromptTitle = transcription.postProcessingPromptTitle
        config.postProcessingRequestSystemPrompt = transcription.postProcessingRequestSystemPrompt
        config.postProcessingRequestUserPrompt = transcription.postProcessingRequestUserPrompt
        config.createdAt = transcription.createdAt
        config.modelName = transcription.modelName
        config.inputSource = transcription.inputSource
        config.transcriptionDuration = transcription.transcriptionDuration
        config.postProcessingDuration = transcription.postProcessingDuration
        config.postProcessingModel = transcription.postProcessingModel
        config.postProcessingFailureReason = transcription.postProcessingFailureReason
        config.postProcessingOutputState = transcription.postProcessingOutputState
        config.transcriptionFailureReason = transcription.transcriptionFailureReason
        config.meetingType = transcription.meetingType
        config.lifecycleState = transcription.lifecycleState
        config.meetingConversationState = transcription.meetingConversationState
        config.executionProvenance = transcription.executionProvenance

        return TranscriptionEntity(meeting: meetingEntity, config: config)
    }

    static func convertToMetadata(_ mo: TranscriptionMO) -> TranscriptionMetadata {
        let wordCount = wordCount(for: mo.text)
        let fallbackName = MeetingApp(rawValue: mo.meeting.appRawValue)?.displayName ?? mo.meeting.appRawValue
        let trimmedDisplayName = mo.meeting.appDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = (trimmedDisplayName?.isEmpty == false) ? trimmedDisplayName! : fallbackName

        return TranscriptionMetadata(
            id: mo.id,
            meetingId: mo.meeting.id,
            meetingTitle: mo.meeting.preferredTitle,
            appName: resolvedName,
            appRawValue: mo.meeting.appRawValue,
            capturePurpose: mo.meeting.capturePurpose,
            appBundleIdentifier: mo.meeting.appBundleIdentifier,
            startTime: mo.meeting.startTime,
            createdAt: mo.createdAt,
            previewText: String(
                TranscriptionDisplayText.preferredPreviewSource(
                    processedContent: mo.processedContent,
                    text: mo.text
                ).prefix(100)
            ),
            wordCount: wordCount,
            language: mo.language,
            isPostProcessed: mo.processedContent != nil,
            postProcessingFailureReason: mo.postProcessingFailureReason,
            duration: mo.meeting.endTime?.timeIntervalSince(mo.meeting.startTime) ?? 0,
            audioFilePath: mo.meeting.audioFilePath,
            inputSource: mo.inputSource,
            lifecycleState: TranscriptionLifecycleState(rawValue: mo.lifecycleStateRawValue) ?? .completed,
            summarySchemaVersion: Int(mo.canonicalSummarySchemaVersion),
            summaryGroundedInTranscript: mo.summaryGroundedInTranscript,
            summaryContainsSpeculation: mo.summaryContainsSpeculation,
            summaryHumanReviewed: mo.summaryHumanReviewed,
            summaryConfidenceScore: mo.summaryConfidenceScore,
            transcriptConfidenceScore: mo.transcriptConfidenceScore,
            transcriptContainsUncertainty: mo.transcriptContainsUncertainty
        )
    }

    static func convertToModel(_ entity: TranscriptionEntity) -> Transcription {
        let meetingEntity = entity.meeting.sanitizedForPersistence()
        let meeting = Meeting(
            id: meetingEntity.id,
            app: MeetingApp(rawValue: meetingEntity.app.rawValue) ?? .unknown,
            capturePurpose: meetingEntity.capturePurpose,
            appBundleIdentifier: meetingEntity.appBundleIdentifier,
            appDisplayName: meetingEntity.appDisplayName,
            title: meetingEntity.title,
            linkedCalendarEvent: meetingEntity.linkedCalendarEvent,
            startTime: meetingEntity.startTime,
            endTime: meetingEntity.endTime,
            audioFilePath: meetingEntity.audioFilePath
        )

        let segments = entity.segments.map { segment in
            Transcription.Segment(
                id: segment.id,
                speaker: segment.speaker,
                text: segment.text,
                startTime: segment.startTime,
                endTime: segment.endTime
            )
        }

        return Transcription(
            id: entity.id,
            meeting: meeting,
            contextItems: entity.contextItems,
            segments: segments,
            text: entity.text,
            rawText: entity.rawText,
            processedContent: entity.processedContent,
            canonicalSummary: entity.canonicalSummary,
            qualityProfile: entity.qualityProfile,
            postProcessingPromptId: entity.postProcessingPromptId,
            postProcessingPromptTitle: entity.postProcessingPromptTitle,
            postProcessingRequestSystemPrompt: entity.postProcessingRequestSystemPrompt,
            postProcessingRequestUserPrompt: entity.postProcessingRequestUserPrompt,
            language: entity.language,
            createdAt: entity.createdAt,
            modelName: entity.modelName,
            inputSource: entity.inputSource,
            transcriptionDuration: entity.transcriptionDuration,
            postProcessingDuration: entity.postProcessingDuration,
            postProcessingModel: entity.postProcessingModel,
            meetingType: entity.meetingType,
            lifecycleState: entity.lifecycleState,
            meetingConversationState: entity.meetingConversationState,
            postProcessingFailureReason: entity.postProcessingFailureReason,
            postProcessingOutputState: entity.postProcessingOutputState,
            transcriptionFailureReason: entity.transcriptionFailureReason,
            executionProvenance: entity.executionProvenance
        )
    }
}

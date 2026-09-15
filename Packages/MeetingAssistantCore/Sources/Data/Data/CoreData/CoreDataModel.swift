import MeetingAssistantCoreDomain

// CoreDataModel - Definição programática do modelo CoreData
// Permite versionamento e migração automática seguindo Clean Architecture

import CoreData
import Foundation

/// Configuração programática do modelo CoreData
// swiftlint:disable:next type_body_length
public enum CoreDataModel {
    /// Versão atual do modelo
    public static let currentVersion = "1.6"

    /// Cria o modelo CoreData programaticamente
    // swiftlint:disable function_body_length
    public static func createManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        // Entidade Meeting
        let meetingEntity = NSEntityDescription()
        meetingEntity.name = "MeetingMO"
        meetingEntity.managedObjectClassName = NSStringFromClass(MeetingMO.self)

        // Atributos Meeting
        let meetingIdAttribute = NSAttributeDescription()
        meetingIdAttribute.name = "id"
        meetingIdAttribute.attributeType = .UUIDAttributeType
        meetingIdAttribute.isOptional = false

        let meetingAppAttribute = NSAttributeDescription()
        meetingAppAttribute.name = "appRawValue"
        meetingAppAttribute.attributeType = .stringAttributeType
        meetingAppAttribute.isOptional = false

        let meetingCapturePurposeAttribute = NSAttributeDescription()
        meetingCapturePurposeAttribute.name = "capturePurposeRawValue"
        meetingCapturePurposeAttribute.attributeType = .stringAttributeType
        meetingCapturePurposeAttribute.isOptional = true

        let meetingAppBundleIdentifierAttribute = NSAttributeDescription()
        meetingAppBundleIdentifierAttribute.name = "appBundleIdentifier"
        meetingAppBundleIdentifierAttribute.attributeType = .stringAttributeType
        meetingAppBundleIdentifierAttribute.isOptional = true

        let meetingAppDisplayNameAttribute = NSAttributeDescription()
        meetingAppDisplayNameAttribute.name = "appDisplayName"
        meetingAppDisplayNameAttribute.attributeType = .stringAttributeType
        meetingAppDisplayNameAttribute.isOptional = true

        let meetingTitleAttribute = NSAttributeDescription()
        meetingTitleAttribute.name = "title"
        meetingTitleAttribute.attributeType = .stringAttributeType
        meetingTitleAttribute.isOptional = true

        let meetingLinkedCalendarEventAttribute = NSAttributeDescription()
        meetingLinkedCalendarEventAttribute.name = "linkedCalendarEventData"
        meetingLinkedCalendarEventAttribute.attributeType = .binaryDataAttributeType
        meetingLinkedCalendarEventAttribute.isOptional = true
        meetingLinkedCalendarEventAttribute.allowsExternalBinaryDataStorage = true

        let meetingStartTimeAttribute = NSAttributeDescription()
        meetingStartTimeAttribute.name = "startTime"
        meetingStartTimeAttribute.attributeType = .dateAttributeType
        meetingStartTimeAttribute.isOptional = false

        let meetingEndTimeAttribute = NSAttributeDescription()
        meetingEndTimeAttribute.name = "endTime"
        meetingEndTimeAttribute.attributeType = .dateAttributeType
        meetingEndTimeAttribute.isOptional = true

        let meetingAudioFilePathAttribute = NSAttributeDescription()
        meetingAudioFilePathAttribute.name = "audioFilePath"
        meetingAudioFilePathAttribute.attributeType = .stringAttributeType
        meetingAudioFilePathAttribute.isOptional = true

        meetingEntity.properties = [
            meetingIdAttribute,
            meetingAppAttribute,
            meetingCapturePurposeAttribute,
            meetingAppBundleIdentifierAttribute,
            meetingAppDisplayNameAttribute,
            meetingTitleAttribute,
            meetingLinkedCalendarEventAttribute,
            meetingStartTimeAttribute,
            meetingEndTimeAttribute,
            meetingAudioFilePathAttribute
        ]

        // Entidade TranscriptionSegment
        let segmentEntity = NSEntityDescription()
        segmentEntity.name = "TranscriptionSegmentMO"
        segmentEntity.managedObjectClassName = NSStringFromClass(TranscriptionSegmentMO.self)

        // Atributos TranscriptionSegment
        let segmentIdAttribute = NSAttributeDescription()
        segmentIdAttribute.name = "id"
        segmentIdAttribute.attributeType = .UUIDAttributeType
        segmentIdAttribute.isOptional = false

        let segmentSpeakerAttribute = NSAttributeDescription()
        segmentSpeakerAttribute.name = "speaker"
        segmentSpeakerAttribute.attributeType = .stringAttributeType
        segmentSpeakerAttribute.isOptional = false

        let segmentTextAttribute = NSAttributeDescription()
        segmentTextAttribute.name = "text"
        segmentTextAttribute.attributeType = .stringAttributeType
        segmentTextAttribute.isOptional = false

        let segmentStartTimeAttribute = NSAttributeDescription()
        segmentStartTimeAttribute.name = "startTime"
        segmentStartTimeAttribute.attributeType = .doubleAttributeType
        segmentStartTimeAttribute.isOptional = false

        let segmentEndTimeAttribute = NSAttributeDescription()
        segmentEndTimeAttribute.name = "endTime"
        segmentEndTimeAttribute.attributeType = .doubleAttributeType
        segmentEndTimeAttribute.isOptional = false

        segmentEntity.properties = [
            segmentIdAttribute,
            segmentSpeakerAttribute,
            segmentTextAttribute,
            segmentStartTimeAttribute,
            segmentEndTimeAttribute
        ]

        // Entidade ModelPerformanceAttempt
        let attemptEntity = NSEntityDescription()
        attemptEntity.name = "ModelPerformanceAttemptMO"
        attemptEntity.managedObjectClassName = NSStringFromClass(ModelPerformanceAttemptMO.self)

        let attemptIdAttribute = NSAttributeDescription()
        attemptIdAttribute.name = "id"
        attemptIdAttribute.attributeType = .UUIDAttributeType
        attemptIdAttribute.isOptional = false

        let attemptTranscriptionIdAttribute = NSAttributeDescription()
        attemptTranscriptionIdAttribute.name = "transcriptionID"
        attemptTranscriptionIdAttribute.attributeType = .UUIDAttributeType
        attemptTranscriptionIdAttribute.isOptional = false

        let attemptStageAttribute = NSAttributeDescription()
        attemptStageAttribute.name = "stageRawValue"
        attemptStageAttribute.attributeType = .stringAttributeType
        attemptStageAttribute.isOptional = false

        let attemptKindAttribute = NSAttributeDescription()
        attemptKindAttribute.name = "attemptKindRawValue"
        attemptKindAttribute.attributeType = .stringAttributeType
        attemptKindAttribute.isOptional = false

        let attemptCapturePurposeAttribute = NSAttributeDescription()
        attemptCapturePurposeAttribute.name = "capturePurposeRawValue"
        attemptCapturePurposeAttribute.attributeType = .stringAttributeType
        attemptCapturePurposeAttribute.isOptional = false

        let attemptProviderIdAttribute = NSAttributeDescription()
        attemptProviderIdAttribute.name = "providerID"
        attemptProviderIdAttribute.attributeType = .stringAttributeType
        attemptProviderIdAttribute.isOptional = false

        let attemptProviderDisplayNameAttribute = NSAttributeDescription()
        attemptProviderDisplayNameAttribute.name = "providerDisplayName"
        attemptProviderDisplayNameAttribute.attributeType = .stringAttributeType
        attemptProviderDisplayNameAttribute.isOptional = false

        let attemptModelIdAttribute = NSAttributeDescription()
        attemptModelIdAttribute.name = "modelID"
        attemptModelIdAttribute.attributeType = .stringAttributeType
        attemptModelIdAttribute.isOptional = false

        let attemptModelDisplayNameAttribute = NSAttributeDescription()
        attemptModelDisplayNameAttribute.name = "modelDisplayName"
        attemptModelDisplayNameAttribute.attributeType = .stringAttributeType
        attemptModelDisplayNameAttribute.isOptional = false

        let attemptRuntimeKindAttribute = NSAttributeDescription()
        attemptRuntimeKindAttribute.name = "runtimeKindRawValue"
        attemptRuntimeKindAttribute.attributeType = .stringAttributeType
        attemptRuntimeKindAttribute.isOptional = false

        let attemptStatusAttribute = NSAttributeDescription()
        attemptStatusAttribute.name = "statusRawValue"
        attemptStatusAttribute.attributeType = .stringAttributeType
        attemptStatusAttribute.isOptional = false

        let attemptStartedAtAttribute = NSAttributeDescription()
        attemptStartedAtAttribute.name = "startedAt"
        attemptStartedAtAttribute.attributeType = .dateAttributeType
        attemptStartedAtAttribute.isOptional = false

        let attemptCompletedAtAttribute = NSAttributeDescription()
        attemptCompletedAtAttribute.name = "completedAt"
        attemptCompletedAtAttribute.attributeType = .dateAttributeType
        attemptCompletedAtAttribute.isOptional = false

        let attemptWallClockAttribute = NSAttributeDescription()
        attemptWallClockAttribute.name = "wallClockSeconds"
        attemptWallClockAttribute.attributeType = .doubleAttributeType
        attemptWallClockAttribute.isOptional = false
        attemptWallClockAttribute.defaultValue = 0.0

        let attemptAudioSecondsAttribute = NSAttributeDescription()
        attemptAudioSecondsAttribute.name = "audioSeconds"
        attemptAudioSecondsAttribute.attributeType = .doubleAttributeType
        attemptAudioSecondsAttribute.isOptional = false
        attemptAudioSecondsAttribute.defaultValue = 0.0

        let attemptInputUTF8BytesAttribute = NSAttributeDescription()
        attemptInputUTF8BytesAttribute.name = "inputUTF8Bytes"
        attemptInputUTF8BytesAttribute.attributeType = .integer64AttributeType
        attemptInputUTF8BytesAttribute.isOptional = false
        attemptInputUTF8BytesAttribute.defaultValue = 0

        let attemptInputCharacterCountAttribute = NSAttributeDescription()
        attemptInputCharacterCountAttribute.name = "inputCharacterCount"
        attemptInputCharacterCountAttribute.attributeType = .integer64AttributeType
        attemptInputCharacterCountAttribute.isOptional = false
        attemptInputCharacterCountAttribute.defaultValue = 0

        let attemptOutputCharacterCountAttribute = NSAttributeDescription()
        attemptOutputCharacterCountAttribute.name = "outputCharacterCount"
        attemptOutputCharacterCountAttribute.attributeType = .integer64AttributeType
        attemptOutputCharacterCountAttribute.isOptional = false
        attemptOutputCharacterCountAttribute.defaultValue = 0

        let attemptFailureReasonAttribute = NSAttributeDescription()
        attemptFailureReasonAttribute.name = "failureReason"
        attemptFailureReasonAttribute.attributeType = .stringAttributeType
        attemptFailureReasonAttribute.isOptional = true

        let attemptExecutionProvenanceAttribute = NSAttributeDescription()
        attemptExecutionProvenanceAttribute.name = "executionProvenanceData"
        attemptExecutionProvenanceAttribute.attributeType = .binaryDataAttributeType
        attemptExecutionProvenanceAttribute.isOptional = true
        attemptExecutionProvenanceAttribute.allowsExternalBinaryDataStorage = true

        attemptEntity.properties = [
            attemptIdAttribute,
            attemptTranscriptionIdAttribute,
            attemptStageAttribute,
            attemptKindAttribute,
            attemptCapturePurposeAttribute,
            attemptProviderIdAttribute,
            attemptProviderDisplayNameAttribute,
            attemptModelIdAttribute,
            attemptModelDisplayNameAttribute,
            attemptRuntimeKindAttribute,
            attemptStatusAttribute,
            attemptStartedAtAttribute,
            attemptCompletedAtAttribute,
            attemptWallClockAttribute,
            attemptAudioSecondsAttribute,
            attemptInputUTF8BytesAttribute,
            attemptInputCharacterCountAttribute,
            attemptOutputCharacterCountAttribute,
            attemptFailureReasonAttribute,
            attemptExecutionProvenanceAttribute
        ]

        // Entidade Transcription
        let transcriptionEntity = NSEntityDescription()
        transcriptionEntity.name = "TranscriptionMO"
        transcriptionEntity.managedObjectClassName = NSStringFromClass(TranscriptionMO.self)

        // Atributos Transcription
        let transcriptionIdAttribute = NSAttributeDescription()
        transcriptionIdAttribute.name = "id"
        transcriptionIdAttribute.attributeType = .UUIDAttributeType
        transcriptionIdAttribute.isOptional = false

        let transcriptionTextAttribute = NSAttributeDescription()
        transcriptionTextAttribute.name = "text"
        transcriptionTextAttribute.attributeType = .stringAttributeType
        transcriptionTextAttribute.isOptional = false

        let transcriptionRawTextAttribute = NSAttributeDescription()
        transcriptionRawTextAttribute.name = "rawText"
        transcriptionRawTextAttribute.attributeType = .stringAttributeType
        transcriptionRawTextAttribute.isOptional = false

        let transcriptionProcessedContentAttribute = NSAttributeDescription()
        transcriptionProcessedContentAttribute.name = "processedContent"
        transcriptionProcessedContentAttribute.attributeType = .stringAttributeType
        transcriptionProcessedContentAttribute.isOptional = true

        let transcriptionPromptIdAttribute = NSAttributeDescription()
        transcriptionPromptIdAttribute.name = "postProcessingPromptId"
        transcriptionPromptIdAttribute.attributeType = .UUIDAttributeType
        transcriptionPromptIdAttribute.isOptional = true

        let transcriptionPromptTitleAttribute = NSAttributeDescription()
        transcriptionPromptTitleAttribute.name = "postProcessingPromptTitle"
        transcriptionPromptTitleAttribute.attributeType = .stringAttributeType
        transcriptionPromptTitleAttribute.isOptional = true

        let transcriptionRequestSystemPromptAttribute = NSAttributeDescription()
        transcriptionRequestSystemPromptAttribute.name = "postProcessingRequestSystemPrompt"
        transcriptionRequestSystemPromptAttribute.attributeType = .stringAttributeType
        transcriptionRequestSystemPromptAttribute.isOptional = true
        transcriptionRequestSystemPromptAttribute.allowsExternalBinaryDataStorage = true

        let transcriptionRequestUserPromptAttribute = NSAttributeDescription()
        transcriptionRequestUserPromptAttribute.name = "postProcessingRequestUserPrompt"
        transcriptionRequestUserPromptAttribute.attributeType = .stringAttributeType
        transcriptionRequestUserPromptAttribute.isOptional = true
        transcriptionRequestUserPromptAttribute.allowsExternalBinaryDataStorage = true

        let transcriptionLanguageAttribute = NSAttributeDescription()
        transcriptionLanguageAttribute.name = "language"
        transcriptionLanguageAttribute.attributeType = .stringAttributeType
        transcriptionLanguageAttribute.isOptional = false

        let transcriptionCreatedAtAttribute = NSAttributeDescription()
        transcriptionCreatedAtAttribute.name = "createdAt"
        transcriptionCreatedAtAttribute.attributeType = .dateAttributeType
        transcriptionCreatedAtAttribute.isOptional = false

        let transcriptionModelNameAttribute = NSAttributeDescription()
        transcriptionModelNameAttribute.name = "modelName"
        transcriptionModelNameAttribute.attributeType = .stringAttributeType
        transcriptionModelNameAttribute.isOptional = false

        // New Metadata Fields
        let transcriptionInputSourceAttribute = NSAttributeDescription()
        transcriptionInputSourceAttribute.name = "inputSource"
        transcriptionInputSourceAttribute.attributeType = .stringAttributeType
        transcriptionInputSourceAttribute.isOptional = true

        let transcriptionDurationAttribute = NSAttributeDescription()
        transcriptionDurationAttribute.name = "transcriptionDuration"
        transcriptionDurationAttribute.attributeType = .doubleAttributeType
        transcriptionDurationAttribute.isOptional = false
        transcriptionDurationAttribute.defaultValue = 0.0

        let postProcessingDurationAttribute = NSAttributeDescription()
        postProcessingDurationAttribute.name = "postProcessingDuration"
        postProcessingDurationAttribute.attributeType = .doubleAttributeType
        postProcessingDurationAttribute.isOptional = false
        postProcessingDurationAttribute.defaultValue = 0.0

        let postProcessingModelAttribute = NSAttributeDescription()
        postProcessingModelAttribute.name = "postProcessingModel"
        postProcessingModelAttribute.attributeType = .stringAttributeType
        postProcessingModelAttribute.isOptional = true

        let postProcessingFailureReasonAttribute = NSAttributeDescription()
        postProcessingFailureReasonAttribute.name = "postProcessingFailureReason"
        postProcessingFailureReasonAttribute.attributeType = .stringAttributeType
        postProcessingFailureReasonAttribute.isOptional = true

        let postProcessingOutputStateAttribute = NSAttributeDescription()
        postProcessingOutputStateAttribute.name = "postProcessingOutputStateRawValue"
        postProcessingOutputStateAttribute.attributeType = .stringAttributeType
        postProcessingOutputStateAttribute.isOptional = true

        let transcriptionFailureReasonAttribute = NSAttributeDescription()
        transcriptionFailureReasonAttribute.name = "transcriptionFailureReason"
        transcriptionFailureReasonAttribute.attributeType = .stringAttributeType
        transcriptionFailureReasonAttribute.isOptional = true

        let meetingTypeAttribute = NSAttributeDescription()
        meetingTypeAttribute.name = "meetingType"
        meetingTypeAttribute.attributeType = .stringAttributeType
        meetingTypeAttribute.isOptional = true

        let lifecycleStateAttribute = NSAttributeDescription()
        lifecycleStateAttribute.name = "lifecycleStateRawValue"
        lifecycleStateAttribute.attributeType = .stringAttributeType
        lifecycleStateAttribute.isOptional = false
        lifecycleStateAttribute.defaultValue = TranscriptionLifecycleState.completed.rawValue

        let meetingConversationStateDataAttribute = NSAttributeDescription()
        meetingConversationStateDataAttribute.name = "meetingConversationStateData"
        meetingConversationStateDataAttribute.attributeType = .binaryDataAttributeType
        meetingConversationStateDataAttribute.isOptional = true
        meetingConversationStateDataAttribute.allowsExternalBinaryDataStorage = true

        let transcriptionContextItemsAttribute = NSAttributeDescription()
        transcriptionContextItemsAttribute.name = "contextItemsData"
        transcriptionContextItemsAttribute.attributeType = .binaryDataAttributeType
        transcriptionContextItemsAttribute.isOptional = true
        transcriptionContextItemsAttribute.allowsExternalBinaryDataStorage = true

        let canonicalSummaryDataAttribute = NSAttributeDescription()
        canonicalSummaryDataAttribute.name = "canonicalSummaryData"
        canonicalSummaryDataAttribute.attributeType = .binaryDataAttributeType
        canonicalSummaryDataAttribute.isOptional = true
        canonicalSummaryDataAttribute.allowsExternalBinaryDataStorage = true

        let transcriptionQualityDataAttribute = NSAttributeDescription()
        transcriptionQualityDataAttribute.name = "transcriptionQualityData"
        transcriptionQualityDataAttribute.attributeType = .binaryDataAttributeType
        transcriptionQualityDataAttribute.isOptional = true
        transcriptionQualityDataAttribute.allowsExternalBinaryDataStorage = true

        let transcriptionExecutionProvenanceAttribute = NSAttributeDescription()
        transcriptionExecutionProvenanceAttribute.name = "executionProvenanceData"
        transcriptionExecutionProvenanceAttribute.attributeType = .binaryDataAttributeType
        transcriptionExecutionProvenanceAttribute.isOptional = true
        transcriptionExecutionProvenanceAttribute.allowsExternalBinaryDataStorage = true

        let canonicalSummarySchemaVersionAttribute = NSAttributeDescription()
        canonicalSummarySchemaVersionAttribute.name = "canonicalSummarySchemaVersion"
        canonicalSummarySchemaVersionAttribute.attributeType = .integer16AttributeType
        canonicalSummarySchemaVersionAttribute.isOptional = false
        canonicalSummarySchemaVersionAttribute.defaultValue = 0

        let summaryGroundedInTranscriptAttribute = NSAttributeDescription()
        summaryGroundedInTranscriptAttribute.name = "summaryGroundedInTranscript"
        summaryGroundedInTranscriptAttribute.attributeType = .booleanAttributeType
        summaryGroundedInTranscriptAttribute.isOptional = false
        summaryGroundedInTranscriptAttribute.defaultValue = false

        let summaryContainsSpeculationAttribute = NSAttributeDescription()
        summaryContainsSpeculationAttribute.name = "summaryContainsSpeculation"
        summaryContainsSpeculationAttribute.attributeType = .booleanAttributeType
        summaryContainsSpeculationAttribute.isOptional = false
        summaryContainsSpeculationAttribute.defaultValue = false

        let summaryHumanReviewedAttribute = NSAttributeDescription()
        summaryHumanReviewedAttribute.name = "summaryHumanReviewed"
        summaryHumanReviewedAttribute.attributeType = .booleanAttributeType
        summaryHumanReviewedAttribute.isOptional = false
        summaryHumanReviewedAttribute.defaultValue = false

        let summaryConfidenceScoreAttribute = NSAttributeDescription()
        summaryConfidenceScoreAttribute.name = "summaryConfidenceScore"
        summaryConfidenceScoreAttribute.attributeType = .doubleAttributeType
        summaryConfidenceScoreAttribute.isOptional = false
        summaryConfidenceScoreAttribute.defaultValue = 0.0

        let transcriptConfidenceScoreAttribute = NSAttributeDescription()
        transcriptConfidenceScoreAttribute.name = "transcriptConfidenceScore"
        transcriptConfidenceScoreAttribute.attributeType = .doubleAttributeType
        transcriptConfidenceScoreAttribute.isOptional = false
        transcriptConfidenceScoreAttribute.defaultValue = 0.5

        let transcriptContainsUncertaintyAttribute = NSAttributeDescription()
        transcriptContainsUncertaintyAttribute.name = "transcriptContainsUncertainty"
        transcriptContainsUncertaintyAttribute.attributeType = .booleanAttributeType
        transcriptContainsUncertaintyAttribute.isOptional = false
        transcriptContainsUncertaintyAttribute.defaultValue = false

        transcriptionEntity.properties = [
            transcriptionIdAttribute,
            transcriptionTextAttribute,
            transcriptionRawTextAttribute,
            transcriptionProcessedContentAttribute,
            transcriptionPromptIdAttribute,
            transcriptionPromptTitleAttribute,
            transcriptionRequestSystemPromptAttribute,
            transcriptionRequestUserPromptAttribute,
            transcriptionLanguageAttribute,
            transcriptionCreatedAtAttribute,
            transcriptionModelNameAttribute,
            transcriptionInputSourceAttribute,
            transcriptionDurationAttribute,
            postProcessingDurationAttribute,
            postProcessingModelAttribute,
            postProcessingFailureReasonAttribute,
            postProcessingOutputStateAttribute,
            transcriptionFailureReasonAttribute,
            meetingTypeAttribute,
            lifecycleStateAttribute,
            meetingConversationStateDataAttribute,
            transcriptionContextItemsAttribute,
            canonicalSummaryDataAttribute,
            transcriptionQualityDataAttribute,
            transcriptionExecutionProvenanceAttribute,
            canonicalSummarySchemaVersionAttribute,
            summaryGroundedInTranscriptAttribute,
            summaryContainsSpeculationAttribute,
            summaryHumanReviewedAttribute,
            summaryConfidenceScoreAttribute,
            transcriptConfidenceScoreAttribute,
            transcriptContainsUncertaintyAttribute
        ]

        // Relacionamentos

        // Transcription -> Meeting (many-to-one)
        let transcriptionToMeetingRelationship = NSRelationshipDescription()
        transcriptionToMeetingRelationship.name = "meeting"
        transcriptionToMeetingRelationship.destinationEntity = meetingEntity
        transcriptionToMeetingRelationship.isOptional = false
        transcriptionToMeetingRelationship.deleteRule = .nullifyDeleteRule
        transcriptionToMeetingRelationship.maxCount = 1 // To-one

        // Meeting -> Transcriptions (one-to-many)
        let meetingToTranscriptionsRelationship = NSRelationshipDescription()
        meetingToTranscriptionsRelationship.name = "transcriptions"
        meetingToTranscriptionsRelationship.destinationEntity = transcriptionEntity
        meetingToTranscriptionsRelationship.inverseRelationship = transcriptionToMeetingRelationship
        meetingToTranscriptionsRelationship.isOptional = true
        meetingToTranscriptionsRelationship.deleteRule = .cascadeDeleteRule
        meetingToTranscriptionsRelationship.maxCount = 0 // To-many

        transcriptionToMeetingRelationship.inverseRelationship = meetingToTranscriptionsRelationship

        // Segment -> Transcription (many-to-one)
        let segmentToTranscriptionRelationship = NSRelationshipDescription()
        segmentToTranscriptionRelationship.name = "transcription"
        segmentToTranscriptionRelationship.destinationEntity = transcriptionEntity
        segmentToTranscriptionRelationship.isOptional = false
        segmentToTranscriptionRelationship.deleteRule = .nullifyDeleteRule
        segmentToTranscriptionRelationship.maxCount = 1 // To-one

        // Transcription -> Segments (one-to-many)
        let transcriptionToSegmentsRelationship = NSRelationshipDescription()
        transcriptionToSegmentsRelationship.name = "segments"
        transcriptionToSegmentsRelationship.destinationEntity = segmentEntity
        transcriptionToSegmentsRelationship.inverseRelationship = segmentToTranscriptionRelationship
        transcriptionToSegmentsRelationship.isOptional = true
        transcriptionToSegmentsRelationship.deleteRule = .cascadeDeleteRule
        transcriptionToSegmentsRelationship.maxCount = 0 // To-many

        segmentToTranscriptionRelationship.inverseRelationship = transcriptionToSegmentsRelationship

        // Attempt -> Transcription (many-to-one)
        let attemptToTranscriptionRelationship = NSRelationshipDescription()
        attemptToTranscriptionRelationship.name = "transcription"
        attemptToTranscriptionRelationship.destinationEntity = transcriptionEntity
        attemptToTranscriptionRelationship.isOptional = false
        attemptToTranscriptionRelationship.deleteRule = .nullifyDeleteRule
        attemptToTranscriptionRelationship.maxCount = 1

        // Transcription -> Attempts (one-to-many)
        let transcriptionToAttemptsRelationship = NSRelationshipDescription()
        transcriptionToAttemptsRelationship.name = "performanceAttempts"
        transcriptionToAttemptsRelationship.destinationEntity = attemptEntity
        transcriptionToAttemptsRelationship.inverseRelationship = attemptToTranscriptionRelationship
        transcriptionToAttemptsRelationship.isOptional = true
        transcriptionToAttemptsRelationship.deleteRule = .cascadeDeleteRule
        transcriptionToAttemptsRelationship.maxCount = 0

        attemptToTranscriptionRelationship.inverseRelationship = transcriptionToAttemptsRelationship

        // Adicionar relacionamentos às entidades
        meetingEntity.properties.append(meetingToTranscriptionsRelationship)
        transcriptionEntity.properties.append(contentsOf: [
            transcriptionToMeetingRelationship,
            transcriptionToSegmentsRelationship,
            transcriptionToAttemptsRelationship
        ])
        segmentEntity.properties.append(segmentToTranscriptionRelationship)
        attemptEntity.properties.append(attemptToTranscriptionRelationship)

        // Adicionar entidades ao modelo
        model.entities = [meetingEntity, transcriptionEntity, segmentEntity, attemptEntity]

        return model
    }
    // swiftlint:enable function_body_length
}

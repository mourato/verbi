import CoreData

// CoreDataModel entity graph - Relacionamentos do modelo CoreData
// Extraído de CoreDataModel.swift para manter o arquivo principal abaixo do
// limite de tamanho, sem alterar a definição do modelo.

extension CoreDataModel {
    /// Adiciona os relacionamentos às entidades e registra as entidades no modelo.
    static func attachEntityGraph(
        meetingEntity: NSEntityDescription,
        transcriptionEntity: NSEntityDescription,
        segmentEntity: NSEntityDescription,
        attemptEntity: NSEntityDescription,
        model: NSManagedObjectModel
    ) {
        // Relacionamentos

        // CaptureArtifact -> CaptureSession (many-to-one)
        let transcriptionToMeetingRelationship = NSRelationshipDescription()
        transcriptionToMeetingRelationship.name = "meeting"
        transcriptionToMeetingRelationship.destinationEntity = meetingEntity
        transcriptionToMeetingRelationship.isOptional = false
        transcriptionToMeetingRelationship.deleteRule = .nullifyDeleteRule
        transcriptionToMeetingRelationship.maxCount = 1 // To-one

        // CaptureSession -> Transcriptions (one-to-many)
        let meetingToTranscriptionsRelationship = NSRelationshipDescription()
        meetingToTranscriptionsRelationship.name = "transcriptions"
        meetingToTranscriptionsRelationship.destinationEntity = transcriptionEntity
        meetingToTranscriptionsRelationship.inverseRelationship = transcriptionToMeetingRelationship
        meetingToTranscriptionsRelationship.isOptional = true
        meetingToTranscriptionsRelationship.deleteRule = .cascadeDeleteRule
        meetingToTranscriptionsRelationship.maxCount = 0 // To-many

        transcriptionToMeetingRelationship.inverseRelationship = meetingToTranscriptionsRelationship

        // Segment -> CaptureArtifact (many-to-one)
        let segmentToTranscriptionRelationship = NSRelationshipDescription()
        segmentToTranscriptionRelationship.name = "transcription"
        segmentToTranscriptionRelationship.destinationEntity = transcriptionEntity
        segmentToTranscriptionRelationship.isOptional = false
        segmentToTranscriptionRelationship.deleteRule = .nullifyDeleteRule
        segmentToTranscriptionRelationship.maxCount = 1 // To-one

        // CaptureArtifact -> Segments (one-to-many)
        let transcriptionToSegmentsRelationship = NSRelationshipDescription()
        transcriptionToSegmentsRelationship.name = "segments"
        transcriptionToSegmentsRelationship.destinationEntity = segmentEntity
        transcriptionToSegmentsRelationship.inverseRelationship = segmentToTranscriptionRelationship
        transcriptionToSegmentsRelationship.isOptional = true
        transcriptionToSegmentsRelationship.deleteRule = .cascadeDeleteRule
        transcriptionToSegmentsRelationship.maxCount = 0 // To-many

        segmentToTranscriptionRelationship.inverseRelationship = transcriptionToSegmentsRelationship

        // Attempt -> CaptureArtifact (many-to-one)
        let attemptToTranscriptionRelationship = NSRelationshipDescription()
        attemptToTranscriptionRelationship.name = "transcription"
        attemptToTranscriptionRelationship.destinationEntity = transcriptionEntity
        attemptToTranscriptionRelationship.isOptional = false
        attemptToTranscriptionRelationship.deleteRule = .nullifyDeleteRule
        attemptToTranscriptionRelationship.maxCount = 1

        // CaptureArtifact -> Attempts (one-to-many)
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
    }
}

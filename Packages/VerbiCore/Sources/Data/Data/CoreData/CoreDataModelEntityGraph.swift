import CoreData

extension CoreDataModel {
    static func attachEntityGraph(
        meetingEntity: NSEntityDescription,
        transcriptionEntity: NSEntityDescription,
        segmentEntity: NSEntityDescription,
        attemptEntity: NSEntityDescription,
        model: NSManagedObjectModel
    ) {
        let transcriptionToMeetingRelationship = NSRelationshipDescription()
        transcriptionToMeetingRelationship.name = "meeting"
        transcriptionToMeetingRelationship.destinationEntity = meetingEntity
        transcriptionToMeetingRelationship.isOptional = false
        transcriptionToMeetingRelationship.deleteRule = .nullifyDeleteRule
        transcriptionToMeetingRelationship.maxCount = 1

        let meetingToTranscriptionsRelationship = NSRelationshipDescription()
        meetingToTranscriptionsRelationship.name = "transcriptions"
        meetingToTranscriptionsRelationship.destinationEntity = transcriptionEntity
        meetingToTranscriptionsRelationship.inverseRelationship = transcriptionToMeetingRelationship
        meetingToTranscriptionsRelationship.isOptional = true
        meetingToTranscriptionsRelationship.deleteRule = .cascadeDeleteRule
        meetingToTranscriptionsRelationship.maxCount = 0

        transcriptionToMeetingRelationship.inverseRelationship = meetingToTranscriptionsRelationship

        let segmentToTranscriptionRelationship = NSRelationshipDescription()
        segmentToTranscriptionRelationship.name = "transcription"
        segmentToTranscriptionRelationship.destinationEntity = transcriptionEntity
        segmentToTranscriptionRelationship.isOptional = false
        segmentToTranscriptionRelationship.deleteRule = .nullifyDeleteRule
        segmentToTranscriptionRelationship.maxCount = 1

        let transcriptionToSegmentsRelationship = NSRelationshipDescription()
        transcriptionToSegmentsRelationship.name = "segments"
        transcriptionToSegmentsRelationship.destinationEntity = segmentEntity
        transcriptionToSegmentsRelationship.inverseRelationship = segmentToTranscriptionRelationship
        transcriptionToSegmentsRelationship.isOptional = true
        transcriptionToSegmentsRelationship.deleteRule = .cascadeDeleteRule
        transcriptionToSegmentsRelationship.maxCount = 0

        segmentToTranscriptionRelationship.inverseRelationship = transcriptionToSegmentsRelationship

        let attemptToTranscriptionRelationship = NSRelationshipDescription()
        attemptToTranscriptionRelationship.name = "transcription"
        attemptToTranscriptionRelationship.destinationEntity = transcriptionEntity
        attemptToTranscriptionRelationship.isOptional = false
        attemptToTranscriptionRelationship.deleteRule = .nullifyDeleteRule
        attemptToTranscriptionRelationship.maxCount = 1

        let transcriptionToAttemptsRelationship = NSRelationshipDescription()
        transcriptionToAttemptsRelationship.name = "performanceAttempts"
        transcriptionToAttemptsRelationship.destinationEntity = attemptEntity
        transcriptionToAttemptsRelationship.inverseRelationship = attemptToTranscriptionRelationship
        transcriptionToAttemptsRelationship.isOptional = true
        transcriptionToAttemptsRelationship.deleteRule = .cascadeDeleteRule
        transcriptionToAttemptsRelationship.maxCount = 0

        attemptToTranscriptionRelationship.inverseRelationship = transcriptionToAttemptsRelationship

        meetingEntity.properties.append(meetingToTranscriptionsRelationship)
        transcriptionEntity.properties.append(contentsOf: [
            transcriptionToMeetingRelationship,
            transcriptionToSegmentsRelationship,
            transcriptionToAttemptsRelationship
        ])
        segmentEntity.properties.append(segmentToTranscriptionRelationship)
        attemptEntity.properties.append(attemptToTranscriptionRelationship)

        model.entities = [meetingEntity, transcriptionEntity, segmentEntity, attemptEntity]
    }
}

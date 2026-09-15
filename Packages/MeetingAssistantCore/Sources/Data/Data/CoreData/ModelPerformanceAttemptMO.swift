import CoreData
import Foundation
import MeetingAssistantCoreDomain

@objc(ModelPerformanceAttemptMO)
public final class ModelPerformanceAttemptMO: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var transcriptionID: UUID
    @NSManaged public var stageRawValue: String
    @NSManaged public var attemptKindRawValue: String
    @NSManaged public var capturePurposeRawValue: String
    @NSManaged public var providerID: String
    @NSManaged public var providerDisplayName: String
    @NSManaged public var modelID: String
    @NSManaged public var modelDisplayName: String
    @NSManaged public var runtimeKindRawValue: String
    @NSManaged public var statusRawValue: String
    @NSManaged public var startedAt: Date
    @NSManaged public var completedAt: Date
    @NSManaged public var wallClockSeconds: Double
    @NSManaged public var audioSeconds: Double
    @NSManaged public var inputUTF8Bytes: Int64
    @NSManaged public var inputCharacterCount: Int64
    @NSManaged public var outputCharacterCount: Int64
    @NSManaged public var failureReason: String?
    @NSManaged public var executionProvenanceData: Data?
    @NSManaged public var transcription: TranscriptionMO
}

public extension ModelPerformanceAttemptMO {
    @nonobjc class func fetchRequest() -> NSFetchRequest<ModelPerformanceAttemptMO> {
        let request = NSFetchRequest<ModelPerformanceAttemptMO>(entityName: "ModelPerformanceAttemptMO")
        request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        return request
    }

    @nonobjc class func fetchRequest(forTranscriptionID id: UUID) -> NSFetchRequest<ModelPerformanceAttemptMO> {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "transcriptionID == %@", id as CVarArg)
        return request
    }

    func toDomain() -> ModelPerformanceAttempt {
        ModelPerformanceAttempt(
            id: id,
            transcriptionID: transcriptionID,
            stage: ModelPerformanceStage(rawValue: stageRawValue) ?? .transcription,
            attemptKind: ModelPerformanceAttemptKind(rawValue: attemptKindRawValue) ?? .initial,
            capturePurpose: CapturePurpose(rawValue: capturePurposeRawValue) ?? .meeting,
            modelIdentity: ModelPerformanceModelIdentity(
                providerID: providerID,
                providerDisplayName: providerDisplayName,
                modelID: modelID,
                modelDisplayName: modelDisplayName,
                runtimeKind: ModelPerformanceRuntimeKind(rawValue: runtimeKindRawValue) ?? .unknown
            ),
            status: ModelPerformanceAttemptStatus(rawValue: statusRawValue) ?? .succeeded,
            startedAt: startedAt,
            completedAt: completedAt,
            wallClockSeconds: wallClockSeconds,
            audioSeconds: audioSeconds,
            inputUTF8Bytes: Int(inputUTF8Bytes),
            inputCharacterCount: Int(inputCharacterCount),
            outputCharacterCount: Int(outputCharacterCount),
            failureReason: failureReason,
            executionProvenance: decodeExecutionProvenance()
        )
    }

    func update(from attempt: ModelPerformanceAttempt, transcription: TranscriptionMO) {
        id = attempt.id
        transcriptionID = attempt.transcriptionID
        stageRawValue = attempt.stage.rawValue
        attemptKindRawValue = attempt.attemptKind.rawValue
        capturePurposeRawValue = attempt.capturePurpose.rawValue
        providerID = attempt.modelIdentity.providerID
        providerDisplayName = attempt.modelIdentity.providerDisplayName
        modelID = attempt.modelIdentity.modelID
        modelDisplayName = attempt.modelIdentity.modelDisplayName
        runtimeKindRawValue = attempt.modelIdentity.runtimeKind.rawValue
        statusRawValue = attempt.status.rawValue
        startedAt = attempt.startedAt
        completedAt = attempt.completedAt
        wallClockSeconds = attempt.wallClockSeconds
        audioSeconds = attempt.audioSeconds
        inputUTF8Bytes = Int64(attempt.inputUTF8Bytes)
        inputCharacterCount = Int64(attempt.inputCharacterCount)
        outputCharacterCount = Int64(attempt.outputCharacterCount)
        failureReason = attempt.failureReason
        executionProvenanceData = encodeExecutionProvenance(attempt.executionProvenance)
        self.transcription = transcription
    }

    static func create(
        from attempt: ModelPerformanceAttempt,
        transcription: TranscriptionMO,
        in context: NSManagedObjectContext
    ) -> ModelPerformanceAttemptMO {
        let managedObject = ModelPerformanceAttemptMO(
            entity: resolvedEntityDescription(named: "ModelPerformanceAttemptMO", in: context),
            insertInto: context
        )
        managedObject.update(from: attempt, transcription: transcription)
        return managedObject
    }

    private func decodeExecutionProvenance() -> ExecutionProvenance? {
        guard let data = executionProvenanceData else { return nil }
        return try? JSONDecoder().decode(ExecutionProvenance.self, from: data)
    }

    private func encodeExecutionProvenance(_ provenance: ExecutionProvenance?) -> Data? {
        guard let provenance else { return nil }
        return try? JSONEncoder().encode(provenance)
    }
}

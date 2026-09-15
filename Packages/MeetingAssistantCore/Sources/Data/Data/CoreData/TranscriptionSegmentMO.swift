import MeetingAssistantCoreDomain

// TranscriptionSegmentMO - Managed Object para segmentos de transcrição
// Modelo CoreData thread-safe seguindo Clean Architecture

import CoreData
import Foundation

/// Managed Object para segmentos de transcrição
@objc(TranscriptionSegmentMO)
public final class TranscriptionSegmentMO: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var speaker: String
    @NSManaged public var text: String
    @NSManaged public var startTime: Double
    @NSManaged public var endTime: Double

    /// Relacionamentos
    @NSManaged public var transcription: TranscriptionMO
}

// MARK: - Fetch Requests

public extension TranscriptionSegmentMO {
    /// Fetch request para buscar segmentos de uma transcrição
    @nonobjc class func fetchRequest(for transcriptionId: UUID) -> NSFetchRequest<TranscriptionSegmentMO> {
        let request = NSFetchRequest<TranscriptionSegmentMO>(entityName: "TranscriptionSegmentMO")
        request.predicate = NSPredicate(format: "transcription.id == %@", transcriptionId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "startTime", ascending: true)]
        return request
    }
}

// MARK: - Conversion Methods

extension TranscriptionSegmentMO {
    /// Converte Managed Object para Domain Entity
    func toDomain() -> TranscriptionEntity.Segment {
        TranscriptionEntity.Segment(
            id: id,
            speaker: speaker,
            text: text,
            startTime: startTime,
            endTime: endTime
        )
    }

    /// Atualiza Managed Object com dados da Domain Entity
    func update(from segment: TranscriptionEntity.Segment) {
        id = segment.id
        speaker = segment.speaker
        text = segment.text
        startTime = segment.startTime
        endTime = segment.endTime
    }

    /// Cria novo Managed Object a partir de Domain Entity
    static func create(
        from segment: TranscriptionEntity.Segment,
        transcription: TranscriptionMO,
        in context: NSManagedObjectContext
    ) -> TranscriptionSegmentMO {
        let segmentMO = TranscriptionSegmentMO(
            entity: resolvedEntityDescription(named: "TranscriptionSegmentMO", in: context),
            insertInto: context
        )
        segmentMO.update(from: segment)
        segmentMO.transcription = transcription
        return segmentMO
    }
}

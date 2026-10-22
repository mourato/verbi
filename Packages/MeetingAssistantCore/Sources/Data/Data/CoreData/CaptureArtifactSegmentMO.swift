import MeetingAssistantCoreDomain

// CaptureArtifactSegmentMO - Managed Object para segmentos de transcrição
// Modelo CoreData thread-safe seguindo Clean Architecture

import CoreData
import Foundation

/// Managed Object para segmentos de transcrição
@objc(TranscriptionSegmentMO)
public final class CaptureArtifactSegmentMO: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var speaker: String
    @NSManaged public var text: String
    @NSManaged public var startTime: Double
    @NSManaged public var endTime: Double

    /// Relacionamentos
    @NSManaged public var transcription: CaptureArtifactMO
}

// MARK: - Fetch Requests

public extension CaptureArtifactSegmentMO {
    /// Fetch request para buscar segmentos de uma transcrição
    @nonobjc class func fetchRequest(for transcriptionId: UUID) -> NSFetchRequest<CaptureArtifactSegmentMO> {
        let request = NSFetchRequest<CaptureArtifactSegmentMO>(entityName: "TranscriptionSegmentMO")
        request.predicate = NSPredicate(format: "transcription.id == %@", transcriptionId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "startTime", ascending: true)]
        return request
    }
}

// MARK: - Conversion Methods

extension CaptureArtifactSegmentMO {
    /// Converte Managed Object para Domain Entity
    func toDomain() -> CaptureArtifactEntity.Segment {
        CaptureArtifactEntity.Segment(
            id: id,
            speaker: speaker,
            text: text,
            startTime: startTime,
            endTime: endTime
        )
    }

    /// Atualiza Managed Object com dados da Domain Entity
    func update(from segment: CaptureArtifactEntity.Segment) {
        id = segment.id
        speaker = segment.speaker
        text = segment.text
        startTime = segment.startTime
        endTime = segment.endTime
    }

    /// Cria novo Managed Object a partir de Domain Entity
    static func create(
        from segment: CaptureArtifactEntity.Segment,
        transcription: CaptureArtifactMO,
        in context: NSManagedObjectContext
    ) -> CaptureArtifactSegmentMO {
        let segmentMO = CaptureArtifactSegmentMO(
            entity: resolvedEntityDescription(named: "TranscriptionSegmentMO", in: context),
            insertInto: context
        )
        segmentMO.update(from: segment)
        segmentMO.transcription = transcription
        return segmentMO
    }
}

/// Compatibility name for the frozen Core Data managed-object class.
@available(*, deprecated, renamed: "CaptureArtifactSegmentMO")
public typealias TranscriptionSegmentMO = CaptureArtifactSegmentMO

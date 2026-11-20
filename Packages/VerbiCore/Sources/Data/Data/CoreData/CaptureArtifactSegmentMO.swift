import CoreData
import Foundation
import VerbiCoreDomain

@objc(TranscriptionSegmentMO)
public final class CaptureArtifactSegmentMO: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var speaker: String
    @NSManaged public var text: String
    @NSManaged public var startTime: Double
    @NSManaged public var endTime: Double

    @NSManaged public var transcription: CaptureArtifactMO
}

public extension CaptureArtifactSegmentMO {
    @nonobjc class func fetchRequest(for transcriptionId: UUID) -> NSFetchRequest<CaptureArtifactSegmentMO> {
        let request = NSFetchRequest<CaptureArtifactSegmentMO>(entityName: "TranscriptionSegmentMO")
        request.predicate = NSPredicate(format: "transcription.id == %@", transcriptionId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "startTime", ascending: true)]
        return request
    }
}

extension CaptureArtifactSegmentMO {
    func toDomain() -> CaptureArtifactEntity.Segment {
        CaptureArtifactEntity.Segment(
            id: id,
            speaker: speaker,
            text: text,
            startTime: startTime,
            endTime: endTime
        )
    }

    func update(from segment: CaptureArtifactEntity.Segment) {
        id = segment.id
        speaker = segment.speaker
        text = segment.text
        startTime = segment.startTime
        endTime = segment.endTime
    }

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

@available(*, deprecated, renamed: "CaptureArtifactSegmentMO")
public typealias TranscriptionSegmentMO = CaptureArtifactSegmentMO

import Foundation

public protocol VocabularyReplaceableSegment {
    var id: UUID { get }
    var speaker: String { get }
    var text: String { get }
    var startTime: Double { get }
    var endTime: Double { get }
    init(id: UUID, speaker: String, text: String, startTime: Double, endTime: Double)
}

extension CaptureArtifact.Segment: VocabularyReplaceableSegment {}
extension DomainTranscriptionSegment: VocabularyReplaceableSegment {}

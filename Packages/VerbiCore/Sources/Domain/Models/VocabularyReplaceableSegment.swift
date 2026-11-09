import Foundation

/// A transcription segment whose text can be transformed by vocabulary replacement rules.
///
/// Implementations must preserve segment identity (`id`), speaker attribution (`speaker`), and
/// timestamp boundaries (`startTime`, `endTime`) when text substitutions are applied.
/// Cross-segment phrases are deliberately evaluated per-segment to prevent inventing artificial
/// timing offsets or cross-speaker phrase redistribution.
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

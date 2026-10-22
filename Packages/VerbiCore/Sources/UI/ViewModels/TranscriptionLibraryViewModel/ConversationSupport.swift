import Foundation
import VerbiCoreDomain

extension TranscriptionLibraryViewModel {
    func sortedSegments(_ segments: [CaptureArtifact.Segment]) -> [CaptureArtifact.Segment] {
        segments.sorted(by: Self.segmentSortComparator)
    }
}

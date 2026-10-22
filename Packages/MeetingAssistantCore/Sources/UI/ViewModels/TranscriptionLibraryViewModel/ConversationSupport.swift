import Foundation
import MeetingAssistantCoreDomain

extension TranscriptionLibraryViewModel {
    func sortedSegments(_ segments: [CaptureArtifact.Segment]) -> [CaptureArtifact.Segment] {
        segments.sorted(by: Self.segmentSortComparator)
    }
}

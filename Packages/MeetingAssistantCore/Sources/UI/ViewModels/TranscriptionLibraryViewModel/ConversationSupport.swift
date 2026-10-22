import Foundation
import MeetingAssistantCoreDomain

extension TranscriptionLibraryViewModel {
    func sortedSegments(_ segments: [Transcription.Segment]) -> [Transcription.Segment] {
        segments.sorted(by: Self.segmentSortComparator)
    }
}

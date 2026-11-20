import Foundation
import VerbiCoreDomain

extension MeetingConversationView {
    var hasIdentifiedSpeakers: Bool {
        transcription?.segments.contains { segment in
            let speaker = segment.speaker.trimmingCharacters(in: .whitespacesAndNewlines)
            return !speaker.isEmpty && speaker != CaptureArtifact.unknownSpeaker
        } ?? false
    }

    var plainTranscript: String {
        guard let transcription else { return "" }
        let rawText = transcription.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawText.isEmpty {
            return rawText
        }
        return sortedSegmentsForDisplay.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var sortedSegmentsForDisplay: [CaptureArtifact.Segment] {
        guard let transcription else { return [] }
        return transcription.segments.sorted { lhs, rhs in
            if lhs.startTime != rhs.startTime {
                return lhs.startTime < rhs.startTime
            }
            if lhs.endTime != rhs.endTime {
                return lhs.endTime < rhs.endTime
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

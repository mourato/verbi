import Foundation
import VerbiCoreCommon
import VerbiCoreDomain

/// Shared chip strings for the meeting detail header and the Copy-all text.
///
/// One source of truth for the chip line so the visible chips and the copied
/// plain-text line can never desync.
struct MeetingDetailChipTexts {
    let date: String
    let duration: String?
    let participants: String?
    let allParticipantNames: String
    let source: String

    init(meeting: CaptureSession) {
        date = meeting.startTime.formatted(
            .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()
        )
        duration = meeting.endTime == nil ? nil : meeting.formattedDuration
        let names = (meeting.linkedCalendarEvent?.attendees ?? []).filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        allParticipantNames = names.joined(separator: ", ")
        if names.isEmpty {
            participants = nil
        } else {
            let shown = names.prefix(2).joined(separator: ", ")
            let remaining = names.count - min(2, names.count)
            if remaining > 0 {
                participants = "\(shown) \("meeting.detail.participants.remaining".localized(with: remaining))"
            } else {
                participants = shown
            }
        }
        source = meeting.appName
    }

    /// The visible chips joined as one plain-text line.
    var line: String {
        [date, duration, participants, source].compactMap(\.self).joined(separator: " · ")
    }
}

/// The copyable texts of one meeting, backing the header Copy menu.
///
/// `transcript` mirrors the Transcript tab: one block per segment with speaker
/// and time range, falling back to the plain transcription text.
struct MeetingCopyContent {
    let title: String
    let chipsLine: String
    let summary: String
    let transcript: String
    let notes: String

    init(
        meeting: CaptureSession,
        summary: String,
        sortedSegments: [CaptureArtifact.Segment],
        fallbackTranscript: String,
        notes: String
    ) {
        title = meeting.resolvedTitle
        chipsLine = MeetingDetailChipTexts(meeting: meeting).line
        self.summary = summary
        if sortedSegments.isEmpty {
            transcript = fallbackTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            transcript = sortedSegments.map { segment in
                let range = "[\(Self.timestamp(segment.startTime))–\(Self.timestamp(segment.endTime))]"
                return "\(segment.speaker) \(range)\n\(segment.text)"
            }.joined(separator: "\n\n")
        }
        self.notes = notes
    }

    var hasSummary: Bool {
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasTranscript: Bool {
        !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasNotes: Bool {
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasAnything: Bool {
        hasSummary || hasTranscript || hasNotes
    }

    /// Markdown with `# <title>`, the chip line, then each non-empty section.
    func copyAllMarkdown() -> String {
        var blocks = ["# \(title)", chipsLine]
        if hasSummary {
            blocks.append("## \("transcription.qa.tab.summary".localized)\n\(summary)")
        }
        if hasNotes {
            blocks.append("## \("transcription.qa.tab.notes".localized)\n\(notes)")
        }
        if hasTranscript {
            blocks.append("## \("transcription.qa.tab.transcript".localized)\n\(transcript)")
        }
        return blocks.joined(separator: "\n\n")
    }

    private static func timestamp(_ value: Double) -> String {
        let totalSeconds = max(0, Int(value.rounded()))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

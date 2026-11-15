import Foundation
import VerbiCoreCommon
import VerbiCoreDomain

/// Shared mm:ss timestamp for the Transcript tab and the copied transcript text.
///
/// One implementation so the on-screen evidence timestamps and the clipboard
/// can never format differently.
func formatSegmentTimestamp(_ value: Double) -> String {
    let totalSeconds = max(0, Int(value.rounded()))
    return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
}

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
/// `summary` is nil when no post-processed summary exists, so the Copy summary
/// item disables itself and Copy-all skips the section instead of copying the
/// display placeholder or duplicating the transcript. The transcript text is
/// computed on demand so rebuilding this value (e.g. on every keystroke in the
/// Notes tab) never joins the segments.
struct MeetingCopyContent {
    let title: String
    let chipsLine: String
    let summary: String?
    let notes: String
    private let sortedSegments: [CaptureArtifact.Segment]
    private let fallbackTranscript: String

    init(
        meeting: CaptureSession,
        summary: String?,
        sortedSegments: [CaptureArtifact.Segment],
        fallbackTranscript: String,
        notes: String
    ) {
        title = meeting.resolvedTitle
        chipsLine = MeetingDetailChipTexts(meeting: meeting).line
        let trimmedSummary = summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = trimmedSummary?.isEmpty == false ? trimmedSummary : nil
        self.sortedSegments = sortedSegments
        self.fallbackTranscript = fallbackTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        self.notes = notes
    }

    var hasSummary: Bool {
        summary != nil
    }

    var hasTranscript: Bool {
        !sortedSegments.isEmpty || !fallbackTranscript.isEmpty
    }

    var hasNotes: Bool {
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasAnything: Bool {
        hasSummary || hasTranscript || hasNotes
    }

    /// One block per segment with speaker and time range, or the plain
    /// transcription text when there are no segments.
    var transcript: String {
        if sortedSegments.isEmpty {
            fallbackTranscript
        } else {
            sortedSegments.map { segment in
                let range = "[\(formatSegmentTimestamp(segment.startTime))–\(formatSegmentTimestamp(segment.endTime))]"
                return "\(segment.speaker) \(range)\n\(segment.text)"
            }.joined(separator: "\n\n")
        }
    }

    /// Markdown with `# <title>`, the chip line, then each non-empty section.
    func copyAllMarkdown() -> String {
        var blocks = ["# \(title)", chipsLine]
        if let summary {
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
}

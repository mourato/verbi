import Foundation
import VerbiCoreDomain

public struct MarkdownRenderer: Sendable {
    public init() {}

    public func render(meeting: CaptureSession, transcription: CaptureArtifact) -> String {
        var markdown = ""

        markdown += "# \(meetingTitle(for: meeting))\n\n"

        let metadataHeader = "export.section.metadata".localized
        markdown += "## \(metadataHeader)\n"

        let dateLabel = "export.label.date".localized
        markdown += "- **\(dateLabel)**: \(formatDate(meeting.startTime))\n"

        let durationLabel = "export.label.duration".localized
        markdown += "- **\(durationLabel)**: \(meeting.formattedDuration)\n"

        let typeLabel = "export.label.type".localized
        markdown += "- **\(typeLabel)**: \(meeting.type.displayName)\n"

        let appLabel = "export.label.app".localized
        markdown += "- **\(appLabel)**: \(meeting.app.displayName)\n\n"

        if let processedContent = transcription.processedContent, !processedContent.isEmpty {
            let summaryHeader = "export.section.ai_summary".localized
            markdown += "## \(summaryHeader)\n\n"
            markdown += processedContent + "\n\n"
        }

        let transcriptionHeader = "export.section.transcription".localized
        markdown += "## \(transcriptionHeader)\n\n"

        let sortedSegments = transcription.segments.sorted { lhs, rhs in
            if lhs.startTime != rhs.startTime {
                return lhs.startTime < rhs.startTime
            }
            if lhs.endTime != rhs.endTime {
                return lhs.endTime < rhs.endTime
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        if !sortedSegments.isEmpty {
            for segment in sortedSegments {
                let time = formatTime(segment.startTime)
                markdown += "**\(segment.speaker)** (\(time)):\n"
                markdown += "\(segment.text)\n\n"
            }
        } else {
            markdown += transcription.text
        }

        return markdown
    }

    public func renderWithTemplate(_ template: String, meeting: CaptureSession, transcription: CaptureArtifact) -> String {
        var output = template

        let summary: String = {
            if let processed = transcription.processedContent, !processed.isEmpty {
                return processed
            }
            return transcription.text
        }()

        output = output.replacingOccurrences(of: "{{title}}", with: meetingTitle(for: meeting))
        output = output.replacingOccurrences(of: "{{date}}", with: formatDate(meeting.startTime))
        output = output.replacingOccurrences(of: "{{duration}}", with: meeting.formattedDuration)
        output = output.replacingOccurrences(of: "{{type}}", with: meeting.type.displayName)
        output = output.replacingOccurrences(of: "{{meetingType}}", with: meeting.type.displayName)
        output = output.replacingOccurrences(of: "{{app}}", with: meeting.app.displayName)
        output = output.replacingOccurrences(of: "{{summary}}", with: summary)

        if output.contains("{{transcription}}") {
            var transcriptionText = ""
            let sortedSegments = transcription.segments.sorted { lhs, rhs in
                if lhs.startTime != rhs.startTime {
                    return lhs.startTime < rhs.startTime
                }
                if lhs.endTime != rhs.endTime {
                    return lhs.endTime < rhs.endTime
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            if !sortedSegments.isEmpty {
                for segment in sortedSegments {
                    let time = formatTime(segment.startTime)
                    transcriptionText += "**\(segment.speaker)** (\(time)):\n\(segment.text)\n\n"
                }
            } else {
                transcriptionText = transcription.text
            }
            output = output.replacingOccurrences(of: "{{transcription}}", with: transcriptionText)
        }
        return output
    }

    private func meetingTitle(for meeting: CaptureSession) -> String {
        meeting.resolvedTitle
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

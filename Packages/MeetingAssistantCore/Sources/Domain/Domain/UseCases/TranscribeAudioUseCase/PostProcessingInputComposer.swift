import Foundation
import MeetingAssistantCoreCommon

/// Builds the canonical prompt input consumed by all post-processing paths.
public enum PostProcessingInputComposer {
    public static func compose(
        transcriptionText: String,
        qualityProfile: TranscriptionQualityProfile,
        context: String?,
        meetingNotes: String?,
        includeQualityMetadata: Bool
    ) -> String {
        var blocks = [transcriptionText]

        if includeQualityMetadata {
            blocks.append(qualityMetadataBlock(from: qualityProfile))
        }

        if let meetingNotes {
            let trimmedNotes = meetingNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedNotes.isEmpty {
                let sanitizedNotes = MeetingNotesMarkdownSanitizer
                    .sanitizeForPromptBlockContent(trimmedNotes)
                blocks.append(
                    """
                    <MEETING_NOTES>
                    \(sanitizedNotes)
                    </MEETING_NOTES>
                    """
                )
            }
        }

        if let context {
            let trimmedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedContext.isEmpty {
                let sanitizedContext = MeetingNotesMarkdownSanitizer
                    .sanitizeForPromptBlockContent(trimmedContext)
                blocks.append(
                    """
                    <CONTEXT_METADATA>
                    \(sanitizedContext)
                    </CONTEXT_METADATA>
                    """
                )
            }
        }

        return blocks.joined(separator: "\n\n")
    }

    private static func qualityMetadataBlock(from qualityProfile: TranscriptionQualityProfile) -> String {
        let markerLines: [String] = if qualityProfile.markers.isEmpty {
            ["none"]
        } else {
            qualityProfile.markers.map { marker in
                "- [\(marker.reason.rawValue)] \(marker.snippet) [\(marker.startTime)-\(marker.endTime)]"
            }
        }

        return """
        <TRANSCRIPT_QUALITY>
        normalizationVersion: \(qualityProfile.normalizationVersion)
        overallConfidence: \(qualityProfile.overallConfidence)
        containsUncertainty: \(qualityProfile.containsUncertainty)
        markers:
        \(markerLines.joined(separator: "\n"))
        </TRANSCRIPT_QUALITY>
        """
    }
}

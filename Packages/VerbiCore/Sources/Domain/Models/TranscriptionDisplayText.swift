import Foundation

/// Shared display-policy helpers for transcription / summary surfaces.
public enum TranscriptionDisplayText {
    /// Detects canonical-summary JSON blobs that must never be shown as prose.
    public static func looksLikeCanonicalSummaryJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") else { return false }
        return trimmed.contains("\"schemaVersion\"") && trimmed.contains("\"summary\"")
    }

    /// Prefer rendered post-processed content, then a non-JSON canonical summary body, then primary text.
    public static func preferredSummary(
        processedContent: String?,
        canonicalSummary: CanonicalSummary?,
        text: String,
        emptyFallback: String
    ) -> String {
        if let processed = sanitizedProse(processedContent) {
            return processed
        }

        if let summary = sanitizedProse(canonicalSummary?.summary) {
            return summary
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, !looksLikeCanonicalSummaryJSON(trimmedText) else {
            return emptyFallback
        }
        return trimmedText
    }

    /// Preview source for list rows: prefer post-processed prose over raw primary text.
    public static func preferredPreviewSource(
        processedContent: String?,
        text: String
    ) -> String {
        if let processed = sanitizedProse(processedContent) {
            return processed
        }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if looksLikeCanonicalSummaryJSON(trimmedText) {
            return ""
        }
        return trimmedText
    }

    private static func sanitizedProse(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !looksLikeCanonicalSummaryJSON(trimmed) else {
            return nil
        }
        return trimmed
    }
}

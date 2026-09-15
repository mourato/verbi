import Foundation

/// Sanitization helpers for meeting-note markdown used in UI rendering and prompt assembly.
public enum MeetingNotesMarkdownSanitizer {
    private static let allowedControlCharacters = CharacterSet(charactersIn: "\n\t")
    private static let reservedPromptTags = [
        "MEETING_NOTES",
        "CONTEXT_METADATA",
        "TRANSCRIPT_QUALITY"
    ]

    /// Normalizes markdown text before rendering by collapsing line endings and stripping unsafe controls.
    public static func sanitizeForMarkdownRendering(_ markdown: String) -> String {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let scalars = normalized.unicodeScalars.filter { scalar in
            guard CharacterSet.controlCharacters.contains(scalar) else { return true }
            return allowedControlCharacters.contains(scalar)
        }

        return String(String.UnicodeScalarView(scalars))
    }

    /// Escapes reserved block tags so user content cannot break prompt wrapper boundaries.
    public static func sanitizeForPromptBlockContent(_ content: String) -> String {
        let normalized = sanitizeForMarkdownRendering(content)
        guard let reservedTagsRegex else {
            return normalized
        }

        let nsString = normalized as NSString
        let mutable = NSMutableString(string: normalized)
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = reservedTagsRegex.matches(in: normalized, options: [], range: fullRange)

        for match in matches.reversed() {
            let token = nsString.substring(with: match.range)
            let escaped = token
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            mutable.replaceCharacters(in: match.range, with: escaped)
        }

        return String(mutable)
    }

    private static let reservedTagsRegex: NSRegularExpression? = {
        let tagsPattern = reservedPromptTags.joined(separator: "|")
        let pattern = "</?(?:\(tagsPattern))>"
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()
}

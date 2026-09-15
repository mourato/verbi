import Foundation

/// Sanitizes post-processing output to prevent context metadata leakage in final user-visible text.
public enum TranscriptionOutputSanitizer {
    public struct Result: Sendable {
        public let text: String?
        public let removedReservedBlocks: Bool
        public let contextLeakDetected: Bool

        public var wasModified: Bool {
            removedReservedBlocks || contextLeakDetected
        }

        public init(
            text: String?,
            removedReservedBlocks: Bool,
            contextLeakDetected: Bool
        ) {
            self.text = text
            self.removedReservedBlocks = removedReservedBlocks
            self.contextLeakDetected = contextLeakDetected
        }
    }

    private static let reservedPromptBlocks = [
        "CONTEXT_METADATA",
        "MEETING_NOTES",
        "TRANSCRIPT_QUALITY"
    ]

    public static func extractContextMetadata(fromPromptInput input: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<\s*CONTEXT_METADATA\s*>([\s\S]*?)<\s*/\s*CONTEXT_METADATA\s*>"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }

        let range = NSRange(input.startIndex ..< input.endIndex, in: input)
        let matches = regex.matches(in: input, options: [], range: range)
        guard !matches.isEmpty else { return nil }

        let extractedBlocks = matches.compactMap { match -> String? in
            guard match.numberOfRanges > 1,
                  let metadataRange = Range(match.range(at: 1), in: input)
            else {
                return nil
            }
            let text = String(input[metadataRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }

        guard !extractedBlocks.isEmpty else { return nil }
        return extractedBlocks.joined(separator: "\n")
    }

    public static func stripPromptMetadata(from text: String) -> String {
        var workingText = text
        for tag in reservedPromptBlocks {
            workingText = removeTagBlock(tag, from: workingText)
        }

        return workingText
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func sanitize(
        processedContent: String?,
        contextMetadata: String?
    ) -> Result {
        guard let processedContent else {
            return Result(text: nil, removedReservedBlocks: false, contextLeakDetected: false)
        }

        var workingText = processedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !workingText.isEmpty else {
            return Result(text: nil, removedReservedBlocks: false, contextLeakDetected: false)
        }

        let metadataStrippedText = stripPromptMetadata(from: workingText)
        let removedReservedBlocks = metadataStrippedText != workingText
        workingText = metadataStrippedText

        guard !workingText.isEmpty else {
            return Result(text: nil, removedReservedBlocks: removedReservedBlocks, contextLeakDetected: false)
        }

        let contextLeakDetected = hasContextLeakage(
            in: workingText,
            contextMetadata: contextMetadata
        )

        if contextLeakDetected {
            return Result(
                text: nil,
                removedReservedBlocks: removedReservedBlocks,
                contextLeakDetected: true
            )
        }

        return Result(
            text: workingText,
            removedReservedBlocks: removedReservedBlocks,
            contextLeakDetected: false
        )
    }

    private static func removeTagBlock(_ tag: String, from text: String) -> String {
        let pattern = #"<\s*"# + NSRegularExpression.escapedPattern(for: tag) + #"\s*>[\s\S]*?<\s*/\s*"# + NSRegularExpression.escapedPattern(for: tag) + #"\s*>"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }

        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    private static func hasContextLeakage(
        in text: String,
        contextMetadata: String?
    ) -> Bool {
        if containsContextMarker(in: text) {
            return true
        }

        guard let contextMetadata else {
            return false
        }

        let trimmedContext = contextMetadata.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContext.isEmpty else {
            return false
        }

        let significantLines = trimmedContext
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 48 }

        var matchedLines = 0
        for line in significantLines.prefix(8)
            where text.range(of: line, options: [.caseInsensitive]) != nil
        {
            matchedLines += 1
            if line.count >= 80 || matchedLines >= 2 {
                return true
            }
        }

        if trimmedContext.count >= 160 {
            let prefix = String(trimmedContext.prefix(120))
            if text.range(of: prefix, options: [.caseInsensitive]) != nil {
                return true
            }
        }

        return false
    }

    private static func containsContextMarker(in text: String) -> Bool {
        let markerPatterns = [
            #"(?i)</?\s*context_metadata\s*>"#,
            #"(?im)^\s*context_metadata\s*$"#
        ]

        return markerPatterns.contains { pattern in
            text.range(of: pattern, options: .regularExpression) != nil
        }
    }
}

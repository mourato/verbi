import Foundation

/// Deterministic find-and-replace rule applied to transcription text.
public struct VocabularyReplacementRule: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var find: String
    public var replace: String

    public init(id: UUID = UUID(), find: String, replace: String) {
        self.id = id
        self.find = find
        self.replace = replace
    }

    public var normalizedFindVariants: [String] {
        Self.normalizedVariants(from: find)
    }

    public static func normalizedVariants(from rawFind: String) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for candidate in rawFind.split(separator: ",", omittingEmptySubsequences: false) {
            let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            let dedupeKey = normalized.lowercased()
            guard !normalized.isEmpty, seen.insert(dedupeKey).inserted else {
                continue
            }
            ordered.append(normalized)
        }

        return ordered
    }

    public static func apply(rules: [VocabularyReplacementRule], to text: String) -> String {
        var output = text

        for rule in rules {
            let variants = rule.normalizedFindVariants.sorted {
                if $0.count == $1.count {
                    return $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                }

                return $0.count > $1.count
            }

            for find in variants {
                let escapedFind = NSRegularExpression.escapedPattern(for: find)
                let pattern = "\\b\(escapedFind)\\b"

                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                    continue
                }

                let escapedReplacement = NSRegularExpression.escapedTemplate(for: rule.replace)
                let range = NSRange(output.startIndex ..< output.endIndex, in: output)
                output = regex.stringByReplacingMatches(
                    in: output,
                    options: [],
                    range: range,
                    withTemplate: escapedReplacement
                )
            }
        }

        return output
    }

    public static func apply<Segment: VocabularyReplaceableSegment>(
        rules: [VocabularyReplacementRule],
        to segments: [Segment]
    ) -> [Segment] {
        segments.map { segment in
            Segment(
                id: segment.id,
                speaker: segment.speaker,
                text: apply(rules: rules, to: segment.text),
                startTime: segment.startTime,
                endTime: segment.endTime
            )
        }
    }
}

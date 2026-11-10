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
            let normalized = VocabularyNormalization.spelling(String(candidate))
            let dedupeKey = VocabularyNormalization.originKey(normalized)
            guard !normalized.isEmpty, seen.insert(dedupeKey).inserted else {
                continue
            }
            ordered.append(normalized)
        }

        return ordered
    }

    private struct CandidateMatch {
        let range: Range<String.Index>
        let length: Int
        let ruleIndex: Int
        let variantIndex: Int
        let replacement: String
    }

    public static func apply(rules: [VocabularyReplacementRule], to text: String) -> String {
        guard !rules.isEmpty, !text.isEmpty else { return text }

        let candidates = collectCandidateMatches(rules: rules, text: text)
        guard !candidates.isEmpty else { return text }

        let acceptedMatches = selectNonOverlappingMatches(from: candidates)
        return assembleOutput(text: text, matches: acceptedMatches)
    }

    private struct VariantRuleRef {
        let variant: String
        let ruleIndex: Int
        let variantIndex: Int
        let replacement: String
    }

    private static func collectCandidateMatches(
        rules: [VocabularyReplacementRule],
        text: String
    ) -> [CandidateMatch] {
        var candidates: [CandidateMatch] = []

        for (ruleIndex, rule) in rules.enumerated() {
            let variants = rule.normalizedFindVariants
            for (variantIndex, variant) in variants.enumerated() {
                guard !variant.isEmpty else { continue }
                let target = VariantRuleRef(
                    variant: variant,
                    ruleIndex: ruleIndex,
                    variantIndex: variantIndex,
                    replacement: rule.replace
                )
                appendMatches(for: target, in: text, to: &candidates)
            }
        }

        return candidates
    }

    private static func appendMatches(
        for target: VariantRuleRef,
        in text: String,
        to candidates: inout [CandidateMatch]
    ) {
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let matchRange = text.range(of: target.variant, options: [.caseInsensitive], range: searchStart ..< text.endIndex)
        {
            if isAtBoundary(in: text, range: matchRange, find: target.variant) {
                let length = text.distance(from: matchRange.lowerBound, to: matchRange.upperBound)
                candidates.append(
                    CandidateMatch(
                        range: matchRange,
                        length: length,
                        ruleIndex: target.ruleIndex,
                        variantIndex: target.variantIndex,
                        replacement: target.replacement
                    )
                )
            }
            searchStart = text.index(after: matchRange.lowerBound)
        }
    }

    private static func selectNonOverlappingMatches(
        from candidates: [CandidateMatch]
    ) -> [CandidateMatch] {
        // Longest match wins globally. Deterministic tie-breakers:
        // 1. Earlier start position
        // 2. Original rule registration order
        // 3. Variant definition order
        let sortedCandidates = candidates.sorted { firstCandidate, secondCandidate in
            if firstCandidate.length != secondCandidate.length {
                return firstCandidate.length > secondCandidate.length
            }
            if firstCandidate.range.lowerBound != secondCandidate.range.lowerBound {
                return firstCandidate.range.lowerBound < secondCandidate.range.lowerBound
            }
            if firstCandidate.ruleIndex != secondCandidate.ruleIndex {
                return firstCandidate.ruleIndex < secondCandidate.ruleIndex
            }
            return firstCandidate.variantIndex < secondCandidate.variantIndex
        }

        var acceptedMatches: [CandidateMatch] = []
        for candidate in sortedCandidates {
            let overlaps = acceptedMatches.contains { accepted in
                accepted.range.overlaps(candidate.range)
            }
            if !overlaps {
                acceptedMatches.append(candidate)
            }
        }

        return acceptedMatches.sorted { firstMatch, secondMatch in
            firstMatch.range.lowerBound < secondMatch.range.lowerBound
        }
    }

    private static func assembleOutput(
        text: String,
        matches: [CandidateMatch]
    ) -> String {
        var output = ""
        output.reserveCapacity(text.count)
        var currentIndex = text.startIndex

        for match in matches {
            output.append(contentsOf: text[currentIndex ..< match.range.lowerBound])
            output.append(match.replacement)
            currentIndex = match.range.upperBound
        }
        output.append(contentsOf: text[currentIndex ..< text.endIndex])

        return output
    }

    /// Evaluates whether a matched range sits at valid word/term boundaries in the source text.
    /// Supports literal punctuation identifiers (e.g. `C++`, `.NET`), accents, and avoids word fragment mutation.
    private static func isAtBoundary(
        in text: String,
        range: Range<String.Index>,
        find: String
    ) -> Bool {
        guard let firstFindChar = find.first, let lastFindChar = find.last else {
            return false
        }

        // Left boundary check
        if range.lowerBound > text.startIndex {
            let charBefore = text[text.index(before: range.lowerBound)]
            if isWordChar(firstFindChar) {
                if isWordChar(charBefore) {
                    return false
                }
            } else {
                if isWordChar(charBefore) || charBefore == firstFindChar {
                    return false
                }
            }
        }

        // Right boundary check
        if range.upperBound < text.endIndex {
            let charAfter = text[range.upperBound]
            if isWordChar(lastFindChar) {
                if isWordChar(charAfter) {
                    return false
                }
            } else {
                if isWordChar(charAfter) || charAfter == lastFindChar {
                    return false
                }
            }
        }

        return true
    }

    private static func isWordChar(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    /// Applies vocabulary replacement rules across segments while preserving segment identifiers,
    /// speaker attribution, and start/end timestamps.
    ///
    /// Note: Rules are evaluated on each segment individually. Cross-segment phrases are not replaced
    /// across segment boundaries to prevent fabricating artificial timestamps or re-attributing speakers.
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

import Foundation

/// Preprocesses transcript text before sending it to downstream intelligence stages.
public struct TranscriptIntelligencePreprocessor: Sendable {
    public struct Constants: Sendable {
        public let lowConfidenceThreshold: Double
        public let veryLowConfidenceThreshold: Double

        public init(
            lowConfidenceThreshold: Double = 0.80,
            veryLowConfidenceThreshold: Double = 0.65
        ) {
            self.lowConfidenceThreshold = lowConfidenceThreshold
            self.veryLowConfidenceThreshold = veryLowConfidenceThreshold
        }
    }

    private let constants: Constants

    public init(constants: Constants = .init()) {
        self.constants = constants
    }

    public func preprocess(
        transcriptionText: String,
        segments: [DomainTranscriptionSegment],
        asrConfidenceScore: Double?
    ) -> TranscriptionQualityProfile {
        let normalizedText = normalizeText(transcriptionText)
        var markers = buildConfidenceMarkers(asrConfidenceScore)
        markers.append(contentsOf: buildLexicalMarkers(in: normalizedText, segments: segments))

        let overallConfidence = computeOverallConfidence(
            asrConfidenceScore: asrConfidenceScore,
            markers: markers
        )

        return TranscriptionQualityProfile(
            normalizedTextForIntelligence: normalizedText,
            overallConfidence: overallConfidence,
            containsUncertainty: !markers.isEmpty,
            markers: deduplicated(markers)
        )
    }

    private func normalizeText(_ text: String) -> String {
        let normalizedNewlines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = normalizedNewlines.components(separatedBy: "\n")
        var normalizedLines: [String] = []
        normalizedLines.reserveCapacity(lines.count)

        var previousWasBlank = false
        for line in lines {
            let compact = collapseInlineWhitespace(line)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if compact.isEmpty {
                if !previousWasBlank {
                    normalizedLines.append("")
                }
                previousWasBlank = true
                continue
            }

            normalizedLines.append(compact)
            previousWasBlank = false
        }

        return normalizedLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func collapseInlineWhitespace(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"[ \t]+"#,
            with: " ",
            options: .regularExpression
        )
    }

    private func buildConfidenceMarkers(_ asrConfidenceScore: Double?) -> [TranscriptionQualityProfile.UncertaintyMarker] {
        guard let asrConfidenceScore else {
            return [
                .init(
                    snippet: "ASR confidence unavailable",
                    reason: .missingConfidence
                )
            ]
        }

        if asrConfidenceScore < constants.veryLowConfidenceThreshold {
            return [
                .init(
                    snippet: String(format: "ASR confidence %.2f", asrConfidenceScore),
                    reason: .veryLowASRConfidence
                )
            ]
        }

        if asrConfidenceScore < constants.lowConfidenceThreshold {
            return [
                .init(
                    snippet: String(format: "ASR confidence %.2f", asrConfidenceScore),
                    reason: .lowASRConfidence
                )
            ]
        }

        return []
    }

    private func buildLexicalMarkers(
        in text: String,
        segments: [DomainTranscriptionSegment]
    ) -> [TranscriptionQualityProfile.UncertaintyMarker] {
        let patterns = [
            #"\[(?:inaudible|unclear|unintelligible|noise|\.{3})\]"#,
            #"\b(?:inaudible|unclear|unintelligible)\b"#,
            #"\?{2,}"#,
            #"\[\.\.\.\]"#
        ]

        return patterns.flatMap { pattern in
            matches(
                pattern: pattern,
                in: text,
                segments: segments
            )
        }
    }

    private func matches(
        pattern: String,
        in text: String,
        segments: [DomainTranscriptionSegment]
    ) -> [TranscriptionQualityProfile.UncertaintyMarker] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let snippetRange = Range(match.range, in: text) else { return nil }
            let snippet = String(text[snippetRange])
            let timing = resolveTiming(for: snippet, in: segments)

            return .init(
                snippet: snippet,
                startTime: timing.startTime,
                endTime: timing.endTime,
                reason: .lexicalUncertainty
            )
        }
    }

    private func resolveTiming(
        for snippet: String,
        in segments: [DomainTranscriptionSegment]
    ) -> (startTime: Double, endTime: Double) {
        let normalizedSnippet = snippet.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedSnippet.isEmpty else {
            return (0, 0)
        }

        if let segment = segments.first(where: { segment in
            segment.text.lowercased().contains(normalizedSnippet)
        }) {
            return (segment.startTime, segment.endTime)
        }

        return (0, 0)
    }

    private func computeOverallConfidence(
        asrConfidenceScore: Double?,
        markers: [TranscriptionQualityProfile.UncertaintyMarker]
    ) -> Double {
        var base = min(1, max(0, asrConfidenceScore ?? 0.5))
        let lexicalCount = markers.count(where: { $0.reason == .lexicalUncertainty })
        let lexicalPenalty = min(0.25, Double(lexicalCount) * 0.03)
        base -= lexicalPenalty
        return min(1, max(0, base))
    }

    private func deduplicated(
        _ markers: [TranscriptionQualityProfile.UncertaintyMarker]
    ) -> [TranscriptionQualityProfile.UncertaintyMarker] {
        var seen = Set<String>()
        var output: [TranscriptionQualityProfile.UncertaintyMarker] = []
        output.reserveCapacity(markers.count)

        for marker in markers {
            let key = "\(marker.reason.rawValue)|\(marker.snippet.lowercased())|\(marker.startTime)|\(marker.endTime)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(marker)
        }

        return output
    }
}

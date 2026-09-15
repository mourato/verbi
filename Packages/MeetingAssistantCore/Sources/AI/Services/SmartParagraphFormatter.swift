import Foundation
import NaturalLanguage

public enum SmartParagraphFormatter {
    private enum Constants {
        static let wordThreshold = 45
        static let substantialSentenceThreshold = 4
        static let minimumSubstantialSentenceWordCount = 4
    }

    public static func format(dictatedText: String) -> String {
        let trimmedText = dictatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return dictatedText }
        guard !looksStructured(trimmedText) else { return dictatedText }

        let sentences = sentenceRanges(in: dictatedText)
        guard sentences.count > 1 else { return dictatedText }

        var paragraphs = [String]()
        var paragraphStart = dictatedText.startIndex
        var paragraphWordCount = 0
        var substantialSentenceCount = 0

        for sentenceRange in sentences {
            let sentence = String(dictatedText[sentenceRange])
            let sentenceWordCount = wordCount(in: sentence)
            paragraphWordCount += sentenceWordCount

            if sentenceWordCount >= Constants.minimumSubstantialSentenceWordCount {
                substantialSentenceCount += 1
            }

            let reachedWordLimit = paragraphWordCount >= Constants.wordThreshold
            let reachedSentenceLimit = substantialSentenceCount >= Constants.substantialSentenceThreshold

            guard reachedWordLimit || reachedSentenceLimit else { continue }

            let paragraph = dictatedText[paragraphStart ..< sentenceRange.upperBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !paragraph.isEmpty {
                paragraphs.append(paragraph)
            }

            paragraphStart = sentenceRange.upperBound
            paragraphWordCount = 0
            substantialSentenceCount = 0
        }

        let trailingParagraph = dictatedText[paragraphStart...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !trailingParagraph.isEmpty {
            paragraphs.append(trailingParagraph)
        }

        guard paragraphs.count > 1 else { return dictatedText }
        return paragraphs.joined(separator: "\n\n")
    }

    private static func sentenceRanges(in text: String) -> [Range<String.Index>] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var ranges = [Range<String.Index>]()
        tokenizer.enumerateTokens(in: text.startIndex ..< text.endIndex) { range, _ in
            ranges.append(range)
            return true
        }
        return ranges
    }

    private static func wordCount(in text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex ..< text.endIndex) { _, _ in
            count += 1
            return true
        }
        return count
    }

    private static func looksStructured(_ text: String) -> Bool {
        if text.contains("\n\n") {
            return true
        }

        let structuredPatterns = [
            #"(?m)^\s*[-*+]\s+"#,
            #"(?m)^\s*\d+\.\s+"#,
            #"(?m)^\s*>\s+"#,
            #"(?m)^\s*#{1,6}\s+"#,
            #"(?m)^\s*```"#
        ]

        return structuredPatterns.contains { pattern in
            text.range(of: pattern, options: .regularExpression) != nil
        }
    }
}

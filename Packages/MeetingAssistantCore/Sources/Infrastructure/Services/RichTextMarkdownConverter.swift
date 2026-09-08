import AppKit
import Foundation

public extension NSAttributedString.Key {
    static let meetingNotesHeadingLevel = NSAttributedString.Key("meetingNotesHeadingLevel")
}

public struct RichTextMarkdownConverter: Sendable {
    public init() {}

    public func convertIfRichText(_ attributedText: NSAttributedString) -> String? {
        guard isRichText(attributedText) else { return nil }
        let converted = convert(attributedText)
        let plain = attributedText.string
        return shouldFallback(converted: converted, plain: plain) ? plain : converted
    }

    public func convert(_ attributedText: NSAttributedString) -> String {
        let normalizedText = normalizeLineBreaks(attributedText.string)
        let baseFontSize = mostCommonFontSize(in: attributedText)
        let fullRange = NSRange(location: 0, length: attributedText.length)
        var outputLines: [String] = []
        var listCounters: [ObjectIdentifier: Int] = [:]

        (normalizedText as NSString).enumerateSubstrings(in: NSRange(location: 0, length: normalizedText.count), options: .byParagraphs) { _, range, _, _ in
            let paragraphRange = NSRange(location: range.location, length: range.length)
            guard paragraphRange.location + paragraphRange.length <= fullRange.length else { return }

            let paragraph = attributedText.attributedSubstring(from: paragraphRange)
            let paragraphString = paragraph.string

            if paragraphString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                outputLines.append("")
                return
            }

            let paragraphStyle = paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            let isCodeBlock = isMonospacedParagraph(paragraph)
            let manualList = manualListMetadata(for: paragraphString)
            let listPrefix = manualList?.prefix ?? listPrefixForParagraph(
                paragraphStyle: paragraphStyle,
                listCounters: &listCounters,
            )
            let headingPrefix = headingPrefixForParagraph(paragraph, baseFontSize: baseFontSize)

            if isCodeBlock {
                outputLines.append("```")
                outputLines.append(paragraphString)
                outputLines.append("```")
                return
            }

            let inlineRange = manualList?.contentRange ?? contentRangeForParagraph(paragraph)
            let inlineParagraph = inlineRange.length > 0
                ? paragraph.attributedSubstring(from: inlineRange)
                : NSAttributedString(string: "")
            let formattedRuns = formatInlineRuns(inlineParagraph)
            let prefix = headingPrefix ?? listPrefix
            let line = prefix == nil ? formattedRuns : "\(prefix!) \(formattedRuns)"
            outputLines.append(line)
        }

        let merged = outputLines.joined(separator: "\n")
        let collapsed = collapseBlankLines(in: merged)
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isRichText(_ attributedText: NSAttributedString) -> Bool {
        var rich = false
        let fullRange = NSRange(location: 0, length: attributedText.length)

        attributedText.enumerateAttributes(in: fullRange, options: []) { attributes, _, stop in
            if attributes[.link] != nil {
                rich = true
                stop.pointee = true
                return
            }

            if let font = attributes[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                if traits.contains(.bold) || traits.contains(.italic) || traits.contains(.monoSpace) {
                    rich = true
                    stop.pointee = true
                    return
                }
            }

            if let style = attributes[.paragraphStyle] as? NSParagraphStyle,
               !style.textLists.isEmpty
            {
                rich = true
                stop.pointee = true
                return
            }
        }

        return rich
    }

    private func formatInlineRuns(_ attributedText: NSAttributedString) -> String {
        var result = ""
        let fullRange = NSRange(location: 0, length: attributedText.length)

        attributedText.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            let substring = attributedText.attributedSubstring(from: range).string
            guard !substring.isEmpty else { return }

            if let link = attributes[.link] {
                let urlString = (link as? URL)?.absoluteString ?? String(describing: link)
                result += "[\(substring)](\(urlString))"
                return
            }

            var wrapped = substring
            if let font = attributes[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                if traits.contains(.monoSpace) {
                    wrapped = "`\(wrapped)`"
                }

                if traits.contains(.bold) {
                    wrapped = "**\(wrapped)**"
                }

                if traits.contains(.italic) {
                    wrapped = "_\(wrapped)_"
                }
            }

            result += wrapped
        }

        return result
    }

    private func listPrefixForParagraph(
        paragraphStyle: NSParagraphStyle?,
        listCounters: inout [ObjectIdentifier: Int],
    ) -> String? {
        guard let textList = paragraphStyle?.textLists.first else { return nil }
        let identifier = ObjectIdentifier(textList)
        let nextValue = (listCounters[identifier] ?? 0) + 1
        listCounters[identifier] = nextValue
        return textList.marker(forItemNumber: nextValue).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func headingPrefixForParagraph(_ paragraph: NSAttributedString, baseFontSize: CGFloat?) -> String? {
        if paragraph.length > 0,
           let explicitHeading = paragraph.attribute(
               .meetingNotesHeadingLevel,
               at: 0,
               effectiveRange: nil,
           ) as? Int,
           (1...6).contains(explicitHeading)
        {
            return String(repeating: "#", count: explicitHeading)
        }

        guard let baseFontSize else { return nil }
        guard let font = paragraph.attribute(.font, at: 0, effectiveRange: nil) as? NSFont else { return nil }

        let size = font.pointSize
        if size >= baseFontSize + 11 {
            return "#"
        }
        if size >= baseFontSize + 9 {
            return "##"
        }
        if size >= baseFontSize + 7 {
            return "###"
        }
        if size >= baseFontSize + 5 {
            return "####"
        }
        if size >= baseFontSize + 3 {
            return "#####"
        }
        if size >= baseFontSize + 1 {
            return "######"
        }

        return nil
    }

    private func manualListMetadata(for paragraphString: String) -> (prefix: String, contentRange: NSRange)? {
        let hasTrailingLineBreak = paragraphString.hasSuffix("\n")
        let content = hasTrailingLineBreak ? String(paragraphString.dropLast()) : paragraphString
        let indent = String(content.prefix { $0 == " " || $0 == "\t" })
        let markerStart = content.index(content.startIndex, offsetBy: indent.count)
        let remainder = String(content[markerStart...])
        let indentPrefix = String(repeating: "    ", count: indentationDepth(for: indent))

        if remainder.hasPrefix("• ") {
            let start = indent.count + 2
            return (
                prefix: indentPrefix + "-",
                contentRange: NSRange(location: start, length: max(0, content.count - start)),
            )
        }

        if remainder.hasPrefix("☐ ") {
            let start = indent.count + 2
            return (
                prefix: indentPrefix + "- [ ]",
                contentRange: NSRange(location: start, length: max(0, content.count - start)),
            )
        }

        if remainder.hasPrefix("☑ ") {
            let start = indent.count + 2
            return (
                prefix: indentPrefix + "- [x]",
                contentRange: NSRange(location: start, length: max(0, content.count - start)),
            )
        }

        if let orderedMatch = orderedListMarker(in: remainder) {
            let start = indent.count + orderedMatch.markerLength
            return (
                prefix: indentPrefix + "\(orderedMatch.number).",
                contentRange: NSRange(location: start, length: max(0, content.count - start)),
            )
        }

        return nil
    }

    private func contentRangeForParagraph(_ paragraph: NSAttributedString) -> NSRange {
        guard paragraph.length > 0 else { return NSRange(location: 0, length: 0) }
        if paragraph.string.hasSuffix("\n") {
            return NSRange(location: 0, length: max(0, paragraph.length - 1))
        }
        return NSRange(location: 0, length: paragraph.length)
    }

    private func indentationDepth(for indent: String) -> Int {
        var depth = 0
        var spaces = 0
        for character in indent {
            if character == "\t" {
                depth += 1
                spaces = 0
            } else if character == " " {
                spaces += 1
                if spaces == 4 {
                    depth += 1
                    spaces = 0
                }
            }
        }
        if spaces > 0 {
            depth += 1
        }
        return depth
    }

    private func orderedListMarker(in value: String) -> (number: Int, markerLength: Int)? {
        var digits = ""
        for character in value {
            guard character.isNumber else { break }
            digits.append(character)
        }

        guard !digits.isEmpty,
              let number = Int(digits)
        else {
            return nil
        }

        let suffixStart = value.index(value.startIndex, offsetBy: digits.count)
        let suffix = value[suffixStart...]
        guard suffix.hasPrefix(". ") else { return nil }

        return (number, digits.count + 2)
    }

    private func isMonospacedParagraph(_ paragraph: NSAttributedString) -> Bool {
        let fullRange = NSRange(location: 0, length: paragraph.length)
        var isMono = true

        paragraph.enumerateAttributes(in: fullRange, options: []) { attributes, _, stop in
            guard let font = attributes[.font] as? NSFont else { return }
            let traits = font.fontDescriptor.symbolicTraits
            if !traits.contains(.monoSpace) {
                isMono = false
                stop.pointee = true
            }
        }

        return isMono
    }

    private func mostCommonFontSize(in attributedText: NSAttributedString) -> CGFloat? {
        var sizeCounts: [CGFloat: Int] = [:]
        let fullRange = NSRange(location: 0, length: attributedText.length)

        attributedText.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            if let font = attributes[.font] as? NSFont {
                sizeCounts[font.pointSize, default: 0] += range.length
            }
        }

        return sizeCounts.max(by: { $0.value < $1.value })?.key
    }

    private func normalizeLineBreaks(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private func collapseBlankLines(in text: String) -> String {
        var output = text
        while output.contains("\n\n\n") {
            output = output.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return output
    }

    private func shouldFallback(converted: String, plain: String) -> Bool {
        let trimmedConverted = converted.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPlain = plain.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedPlain.isEmpty {
            return false
        }

        if trimmedConverted.isEmpty {
            return true
        }

        let minimumLength = max(1, Int(Double(trimmedPlain.count) * 0.5))
        return trimmedConverted.count < minimumLength
    }
}

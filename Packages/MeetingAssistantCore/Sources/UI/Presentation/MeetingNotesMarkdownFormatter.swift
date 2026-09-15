import AppKit
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure

struct MeetingNotesMarkdownFormatter {
    typealias MarkdownParser = (Data, AttributedString.MarkdownParsingOptions) throws -> NSAttributedString

    private let converter: RichTextMarkdownConverter
    private let parser: MarkdownParser
    private let parsingOptions: AttributedString.MarkdownParsingOptions

    init(
        converter: RichTextMarkdownConverter = RichTextMarkdownConverter(),
        parser: @escaping MarkdownParser = { data, options in
            try NSAttributedString(markdown: data, options: options)
        },
        parsingOptions: AttributedString.MarkdownParsingOptions = Self.defaultParsingOptions
    ) {
        self.converter = converter
        self.parser = parser
        self.parsingOptions = parsingOptions
    }

    func attributedStringForEditing(from markdown: String) -> NSAttributedString {
        let sanitized = MeetingNotesMarkdownSanitizer.sanitizeForMarkdownRendering(markdown)
        guard !sanitized.isEmpty else {
            return NSAttributedString(string: "")
        }

        do {
            return try parser(Data(sanitized.utf8), parsingOptions)
        } catch {
            return NSAttributedString(string: sanitized)
        }
    }

    func markdownForPersistence(from attributedText: NSAttributedString) -> String {
        let markdown = converter.convert(attributedText)
        return MeetingNotesMarkdownSanitizer.sanitizeForMarkdownRendering(markdown)
    }

    private static var defaultParsingOptions: AttributedString.MarkdownParsingOptions {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        options.failurePolicy = .returnPartiallyParsedIfPossible
        return options
    }
}

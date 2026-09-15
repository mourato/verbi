import Foundation
import MeetingAssistantCoreDomain

/// Service responsible for exporting meeting data to files.
public struct ExportService: Sendable {
    private let renderer: MarkdownRenderer

    public init(renderer: MarkdownRenderer = MarkdownRenderer()) {
        self.renderer = renderer
    }

    /// Exports the meeting and transcription to a file at the specified URL.
    /// - Parameters:
    ///   - meeting: The meeting entity.
    ///   - transcription: The associated transcription.
    ///   - url: The file URL to save to.
    public func export(meeting: Meeting, transcription: Transcription, to url: URL) throws {
        let content = renderer.render(meeting: meeting, transcription: transcription)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Exports pre-rendered text content to a file at the specified URL.
    /// - Parameters:
    ///   - content: The content to write.
    ///   - url: The file URL to save to.
    public func export(content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Generates a suggested filename for the export.
    /// - Parameter meeting: The meeting entity.
    /// - Returns: A safe filename string (e.g., "Meeting_2023-10-27_Standup.md").
    public func suggestedFilename(for meeting: Meeting) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: meeting.startTime)
        let title = meeting.resolvedTitle
            .components(separatedBy: CharacterSet(charactersIn: "/\\\\?%*|\"<>:"))
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        return "\(date) \(title).md"
    }
}

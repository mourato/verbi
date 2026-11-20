import Foundation
import VerbiCoreDomain

public struct ExportService: Sendable {
    private let renderer: MarkdownRenderer

    public init(renderer: MarkdownRenderer = MarkdownRenderer()) {
        self.renderer = renderer
    }

    public func export(meeting: CaptureSession, transcription: CaptureArtifact, to url: URL) throws {
        let content = renderer.render(meeting: meeting, transcription: transcription)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    public func export(content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    public func suggestedFilename(for meeting: CaptureSession) -> String {
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

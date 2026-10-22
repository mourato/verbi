@testable import MeetingAssistantCore
import XCTest

final class MarkdownRendererTests: XCTestCase {

    func testRenderWithSegments() {
        let meeting = CaptureSession(
            app: .googleMeet,
            type: .standup,
            startTime: Date(timeIntervalSince1970: 1_698_372_000), // 2023-10-27 10:00:00 UTC
        )

        // Mock segments
        let segments = [
            CaptureArtifact.Segment(speaker: "Alice", text: "Hello team.", startTime: 0, endTime: 5),
            CaptureArtifact.Segment(speaker: "Bob", text: "Hi Alice.", startTime: 6, endTime: 10),
        ]

        let transcription = CaptureArtifact(
            meeting: meeting,
            segments: segments,
            text: "Hello team. Hi Alice.",
            rawText: "Hello team. Hi Alice.",
            processedContent: "Alice and Bob greeted each other.",
        )

        let renderer = MarkdownRenderer()
        let output = renderer.render(meeting: meeting, transcription: transcription)

        // Assertions
        XCTAssertTrue(output.contains(meeting.app.displayName))
        XCTAssertTrue(output.contains("- **\("export.label.type".localized)**: \(meeting.type.displayName)"))
        XCTAssertTrue(output.contains("## \("export.section.ai_summary".localized)"))
        XCTAssertTrue(output.contains("Alice and Bob greeted each other."))
        XCTAssertTrue(output.contains("**Alice** (00:00):"))
        XCTAssertTrue(output.contains("Hello team."))
        XCTAssertTrue(output.contains("**Bob** (00:06):"))
        XCTAssertTrue(output.contains("Hi Alice."))
    }

    func testRenderWithoutSegments() {
        let meeting = CaptureSession(app: .slack, type: .general)
        let transcription = CaptureArtifact(
            meeting: meeting,
            text: "Raw text only.",
            rawText: "Raw text only.",
        )

        let renderer = MarkdownRenderer()
        let output = renderer.render(meeting: meeting, transcription: transcription)

        XCTAssertTrue(output.contains("Raw text only."))
        XCTAssertFalse(output.contains("**Speaker**"))
    }
}

final class ExportServiceTests: XCTestCase {

    func testSuggestedFilename() {
        let date = Date(timeIntervalSince1970: 1_698_372_000) // 2023-10-27
        let meeting = CaptureSession(app: .zoom, title: "Weekly Design Review", type: .designReview, startTime: date)

        let service = ExportService()
        let filename = service.suggestedFilename(for: meeting)

        XCTAssertTrue(filename.contains("Weekly Design Review.md"))
        XCTAssertTrue(filename.hasSuffix(".md"))
    }
}

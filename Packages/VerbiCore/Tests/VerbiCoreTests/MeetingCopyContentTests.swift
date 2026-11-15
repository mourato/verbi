@testable import VerbiCore
@testable import VerbiCoreDomain
@testable import VerbiCoreUI
import XCTest

@MainActor
final class MeetingCopyContentTests: XCTestCase {
    private func makeMeeting() -> CaptureSession {
        CaptureSession(
            app: .zoom,
            title: "Launch planning",
            startTime: Date(timeIntervalSince1970: 1_762_795_800),
            endTime: Date(timeIntervalSince1970: 1_762_796_520)
        )
    }

    private func makeContent(
        summary: String? = "The team aligned on scope.",
        segments: [CaptureArtifact.Segment] = [],
        fallbackTranscript: String = "Full transcript text.",
        notes: String = "Follow up Friday."
    ) -> MeetingCopyContent {
        MeetingCopyContent(
            meeting: makeMeeting(),
            summary: summary,
            sortedSegments: segments,
            fallbackTranscript: fallbackTranscript,
            notes: notes
        )
    }

    func testCopyAll_OrdersSectionsAndSkipsEmptyOnes() throws {
        let content = makeContent(summary: nil, notes: "  ")
        let markdown = content.copyAllMarkdown()

        XCTAssertFalse(content.hasSummary)
        XCTAssertFalse(content.hasNotes)
        XCTAssertTrue(content.hasTranscript)
        XCTAssertTrue(markdown.hasPrefix("# Launch planning\n"))
        XCTAssertTrue(markdown.contains(content.chipsLine))

        let transcriptRange = try XCTUnwrap(markdown.range(of: "Full transcript text."))
        XCTAssertFalse(markdown.contains("The team aligned"))
        XCTAssertFalse(markdown.contains("Follow up"))
        // Only title, chips line and the transcript section remain.
        XCTAssertEqual(markdown.components(separatedBy: "\n\n").count, 3)
        XCTAssertLessThan(markdown.startIndex, transcriptRange.lowerBound)
    }

    func testCopyAll_AllSectionsPresentInSpecOrder() throws {
        let content = makeContent()
        let markdown = content.copyAllMarkdown()

        let summaryRange = try XCTUnwrap(markdown.range(of: "The team aligned on scope."))
        let notesRange = try XCTUnwrap(markdown.range(of: "Follow up Friday."))
        let transcriptRange = try XCTUnwrap(markdown.range(of: "Full transcript text."))
        XCTAssertLessThan(summaryRange.lowerBound, notesRange.lowerBound)
        XCTAssertLessThan(notesRange.lowerBound, transcriptRange.lowerBound)
    }

    func testSummary_WithoutPostProcessing_DisablesSummaryWithoutDuplicatingTranscript() {
        // Meeting with transcription text but no processed summary: the Summary
        // tab falls back to the transcript, but the clipboard must not duplicate
        // it under ## Summary, and Copy summary stays disabled.
        let content = makeContent(summary: nil)
        let markdown = content.copyAllMarkdown()

        XCTAssertFalse(content.hasSummary)
        XCTAssertTrue(content.hasTranscript)
        XCTAssertEqual(markdown.components(separatedBy: "\n\n").count, 4)
        XCTAssertEqual(markdown.components(separatedBy: "Full transcript text.").count - 1, 1)
    }

    func testSummary_FailedTranscription_DisablesSummaryAndCopiesNothingThere() {
        // Empty text, no processed content, no canonical summary: the display
        // placeholder must never reach the clipboard.
        let content = makeContent(summary: nil, fallbackTranscript: "", notes: "")
        let markdown = content.copyAllMarkdown()

        XCTAssertFalse(content.hasSummary)
        XCTAssertFalse(content.hasTranscript)
        XCTAssertFalse(content.hasNotes)
        XCTAssertFalse(content.hasAnything)
        XCTAssertFalse(markdown.contains("No transcription available"))
        XCTAssertEqual(markdown.components(separatedBy: "\n\n").count, 2)
    }

    func testTranscript_FormatsSegmentsWithSpeakerAndTimeRange() {
        let segments = [
            CaptureArtifact.Segment(speaker: "Kara", text: "Hello.", startTime: 61, endTime: 65),
            CaptureArtifact.Segment(speaker: "Ray", text: "Hi.", startTime: 66, endTime: 70)
        ]
        let content = makeContent(segments: segments, fallbackTranscript: "unused")

        XCTAssertTrue(content.hasTranscript)
        XCTAssertTrue(content.transcript.contains("Kara [01:01–01:05]\nHello."))
        XCTAssertTrue(content.transcript.contains("Ray [01:06–01:10]\nHi."))
    }

    func testAvailability_AllEmptyDisablesCopyAll() {
        let content = makeContent(summary: nil, fallbackTranscript: "", notes: "")
        XCTAssertFalse(content.hasAnything)
        XCTAssertEqual(content.copyAllMarkdown().components(separatedBy: "\n\n").count, 2)
    }
}

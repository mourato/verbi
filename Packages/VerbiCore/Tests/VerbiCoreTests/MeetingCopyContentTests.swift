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
        summary: String = "The team aligned on scope.",
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

    func testCopyAll_OrdersSectionsAndSkipsEmptyOnes() {
        let content = makeContent(summary: "", notes: "  ")
        let markdown = content.copyAllMarkdown()

        XCTAssertFalse(content.hasSummary)
        XCTAssertFalse(content.hasNotes)
        XCTAssertTrue(content.hasTranscript)
        XCTAssertTrue(markdown.hasPrefix("# Launch planning\n"))
        XCTAssertTrue(markdown.contains(content.chipsLine))
        XCTAssertFalse(markdown.contains("The team aligned"))
        XCTAssertFalse(markdown.contains("Follow up"))

        let transcriptRange = markdown.range(of: "Full transcript text.")!
        let summaryHeaderRange = markdown.range(of: "##")!
        XCTAssertLessThan(summaryHeaderRange.lowerBound, transcriptRange.lowerBound)
    }

    func testCopyAll_AllSectionsPresentInSpecOrder() {
        let content = makeContent()
        let markdown = content.copyAllMarkdown()

        let summaryIndex = markdown.range(of: "The team aligned on scope.")!.lowerBound
        let notesIndex = markdown.range(of: "Follow up Friday.")!.lowerBound
        let transcriptIndex = markdown.range(of: "Full transcript text.")!.lowerBound
        XCTAssertLessThan(summaryIndex, notesIndex)
        XCTAssertLessThan(notesIndex, transcriptIndex)
    }

    func testTranscript_FormatsSegmentsWithSpeakerAndTimeRange() {
        let segments = [
            CaptureArtifact.Segment(speaker: "Kara", text: "Hello.", startTime: 61, endTime: 65),
            CaptureArtifact.Segment(speaker: "Ray", text: "Hi.", startTime: 66, endTime: 70),
        ]
        let content = makeContent(segments: segments, fallbackTranscript: "unused")

        XCTAssertTrue(content.hasTranscript)
        XCTAssertTrue(content.transcript.contains("Kara [01:01–01:05]\nHello."))
        XCTAssertTrue(content.transcript.contains("Ray [01:06–01:10]\nHi."))
    }

    func testAvailability_AllEmptyDisablesCopyAll() {
        let content = makeContent(summary: "  ", fallbackTranscript: "", notes: "")
        XCTAssertFalse(content.hasAnything)
        XCTAssertEqual(content.copyAllMarkdown().components(separatedBy: "\n\n").count, 2)
    }
}

@testable import MeetingAssistantCore
import XCTest

@MainActor
final class TranscriptionManualExportFilenameTests: XCTestCase {
    func testSummaryExportFilenameDoesNotAppendSummarySuffix() {
        let filename = TranscriptionLibraryViewModel.manualExportSuggestedFilename(
            baseFilename: "2026-03-09 Team Sync",
            kind: .summary,
        )

        XCTAssertEqual(filename, "2026-03-09 Team Sync.md")
    }

    func testOriginalExportFilenameKeepsOriginalSuffix() {
        let filename = TranscriptionLibraryViewModel.manualExportSuggestedFilename(
            baseFilename: "2026-03-09 Team Sync",
            kind: .original,
        )
        let expectedSuffix = "transcription.export.filename.original_suffix".localized

        XCTAssertEqual(filename, "2026-03-09 Team Sync \(expectedSuffix).md")
    }
}

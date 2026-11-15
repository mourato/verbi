@testable import VerbiCore
@testable import VerbiCoreDomain
@testable import VerbiCoreUI
import XCTest

@MainActor
final class MeetingFooterStateTests: XCTestCase {
    func testModelName_BlankOrNil_StaysHidden() {
        XCTAssertNil(MeetingFooterState(postProcessingModel: nil, hasGeneratedSummary: true, isFallback: false).modelName)
        XCTAssertNil(MeetingFooterState(postProcessingModel: "  ", hasGeneratedSummary: true, isFallback: false).modelName)
        XCTAssertEqual(
            MeetingFooterState(postProcessingModel: "Gemini Flash Lite", hasGeneratedSummary: true, isFallback: false).modelName,
            "Gemini Flash Lite"
        )
    }

    func testDisclaimer_ShowsOnlyForGeneratedNonFallbackSummaries() {
        XCTAssertTrue(
            MeetingFooterState(postProcessingModel: nil, hasGeneratedSummary: true, isFallback: false).showsAIDisclaimer
        )
        XCTAssertFalse(
            MeetingFooterState(postProcessingModel: "m", hasGeneratedSummary: true, isFallback: true).showsAIDisclaimer
        )
        XCTAssertFalse(
            MeetingFooterState(postProcessingModel: "m", hasGeneratedSummary: false, isFallback: false).showsAIDisclaimer
        )
    }
}

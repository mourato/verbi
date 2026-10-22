import Foundation
@testable import VerbiCore
import XCTest

final class PostProcessingSystemContextMetadataTests: XCTestCase {
    func testAugment_WithExistingContext_AddsRequestedSystemFields() throws {
        let baseContext = """
        CONTEXT_METADATA
        - Active app: WhatsApp
        - Active window title: WhatsApp
        """

        let resolvedTimeZone = try XCTUnwrap(TimeZone(identifier: "America/Sao_Paulo"))
        let resolvedDate = try XCTUnwrap(isoDate("2026-04-11T22:25:00Z"))

        let enriched = try XCTUnwrap(
            PostProcessingSystemContextMetadata.augment(
                baseContext,
                now: resolvedDate,
                timeZone: resolvedTimeZone,
                locale: Locale(identifier: "en_BR"),
                fullUserName: "Renato",
            ),
        )

        XCTAssertTrue(enriched.contains("- Current time: 2026-04-11, 19:25"))
        XCTAssertTrue(enriched.contains("- Time zone: America/Sao_Paulo"))
        XCTAssertTrue(enriched.contains("- Locale: en_BR"))
        XCTAssertTrue(enriched.contains("- User's full name: Renato"))
        XCTAssertTrue(enriched.contains("- Active app: WhatsApp"))
        XCTAssertTrue(enriched.contains("<SYSTEM_CONTEXT>"))
        XCTAssertTrue(enriched.contains("</SYSTEM_CONTEXT>"))
        XCTAssertFalse(enriched.hasPrefix("CONTEXT_METADATA"))
    }

    func testAugment_DoesNotDuplicateSystemFieldsIfAlreadyPresent() throws {
        let baseContext = """
        CONTEXT_METADATA
        - Time zone: America/Sao_Paulo
        - Locale: en_BR
        - Active app: WhatsApp
        """

        let resolvedTimeZone = try XCTUnwrap(TimeZone(identifier: "America/Sao_Paulo"))
        let resolvedDate = try XCTUnwrap(isoDate("2026-04-11T22:25:00Z"))

        let enriched = try XCTUnwrap(
            PostProcessingSystemContextMetadata.augment(
                baseContext,
                now: resolvedDate,
                timeZone: resolvedTimeZone,
                locale: Locale(identifier: "en_BR"),
                fullUserName: "Renato",
            ),
        )

        XCTAssertEqual(enriched.components(separatedBy: "Time zone:").count - 1, 1)
        XCTAssertEqual(enriched.components(separatedBy: "Locale:").count - 1, 1)
    }

    func testAugment_WithNilContext_ReturnsNil() {
        let enriched = PostProcessingSystemContextMetadata.augment(nil)
        XCTAssertNil(enriched)
    }

    private func isoDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: value)
    }
}

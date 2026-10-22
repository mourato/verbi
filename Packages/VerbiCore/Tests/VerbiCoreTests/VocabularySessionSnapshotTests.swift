@testable import VerbiCoreDomain
import XCTest

/// Confirms incremental finalize inputs use session snapshot contracts (not live settings).
final class VocabularySessionSnapshotTests: XCTestCase {
    func testSessionSnapshotTermsAndRules_RemainStableForFinalizeInputs() {
        let sessionSnapshot = VocabularySnapshot(
            terms: [
                VocabularyTerm(term: "SessionTerm", definition: ""),
            ],
            replacementRules: [
                VocabularyReplacementRule(find: "session find", replace: "session replace"),
            ],
        )

        // Simulate live settings changing after session capture.
        let liveSettingsSnapshot = VocabularySnapshot(
            terms: [
                VocabularyTerm(term: "LiveTerm", definition: ""),
            ],
            replacementRules: [
                VocabularyReplacementRule(find: "live find", replace: "live replace"),
            ],
        )

        XCTAssertNotEqual(sessionSnapshot.terms.map(\.term), liveSettingsSnapshot.terms.map(\.term))
        XCTAssertEqual(sessionSnapshot.terms.map(\.term), ["SessionTerm"])
        XCTAssertEqual(sessionSnapshot.replacementRules.map(\.find), ["session find"])

        // Enhancement + replacement finalize must consume the session snapshot values.
        let enhancementContext = sessionSnapshot.postProcessingContext
        XCTAssertTrue(enhancementContext?.contains("SessionTerm") == true)
        XCTAssertFalse(enhancementContext?.contains("LiveTerm") == true)
    }

    func testDiagnosticsExtrasMustNotIncludeRawVocabularyTerms() {
        let hints = VocabularyProviderHints(groqPrompt: "SecretTerm", elevenLabsKeyterms: ["SecretTerm"])
        let extras: [String: Any] = [
            "hasVocabularyHints": !hints.isEmpty,
            "hasVocabularyKeyterms": !hints.elevenLabsKeyterms.isEmpty,
        ]

        let serialized = extras.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        XCTAssertFalse(serialized.contains("SecretTerm"))
        XCTAssertTrue(serialized.contains("hasVocabularyHints=true"))
        XCTAssertTrue(serialized.contains("hasVocabularyKeyterms=true"))
    }
}

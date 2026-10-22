@testable import VerbiCore
@testable import VerbiCoreUI
import XCTest

@MainActor
final class AssistantVoiceVocabularyTests: XCTestCase {
    func testNormalizedAssistantTranscription_AppliesVocabularyRulesBeforeTrimming() {
        let phase = AssistantTranscriptionPhase(transcriptionClient: .shared)

        let result = phase.normalizedAssistantTranscription(
            "  open ay eye summarize this for reycast  ",
            vocabularyReplacementRules: [
                VocabularyReplacementRule(find: "open ay eye", replace: "OpenAI"),
                VocabularyReplacementRule(find: "reycast, recast", replace: "Raycast"),
            ],
        )

        XCTAssertEqual(result, "OpenAI summarize this for Raycast")
    }

    func testNormalizedAssistantTranscription_ReturnsTrimmedOriginalWhenNoRuleMatches() {
        let phase = AssistantTranscriptionPhase(transcriptionClient: .shared)

        let result = phase.normalizedAssistantTranscription(
            "  ask for status update  ",
            vocabularyReplacementRules: [
                VocabularyReplacementRule(find: "open ay eye", replace: "OpenAI"),
            ],
        )

        XCTAssertEqual(result, "ask for status update")
    }
}

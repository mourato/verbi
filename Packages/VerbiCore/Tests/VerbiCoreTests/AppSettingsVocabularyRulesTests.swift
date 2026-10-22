@testable import VerbiCore
import XCTest

@MainActor
final class AppSettingsVocabularyRulesTests: XCTestCase {
    private var settings: AppSettingsStore!

    override func setUp() async throws {
        settings = .shared
        settings.resetToDefaults()
    }

    override func tearDown() async throws {
        settings.resetToDefaults()
        settings = nil
    }

    func testVocabularyRules_AreNormalizedAndDeduplicatedByFind() {
        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: "  open ay eye  ", replace: " OpenAI "),
            VocabularyReplacementRule(find: "OPEN AY EYE", replace: "SHOULD_NOT_WIN"),
            VocabularyReplacementRule(find: "   ", replace: "ignored"),
            VocabularyReplacementRule(find: "g p t", replace: "GPT"),
        ]

        XCTAssertEqual(settings.vocabularyReplacementRules.count, 2)
        XCTAssertEqual(settings.vocabularyReplacementRules[0].find, "open ay eye")
        XCTAssertEqual(settings.vocabularyReplacementRules[0].replace, "OpenAI")
        XCTAssertEqual(settings.vocabularyReplacementRules[1].find, "g p t")
        XCTAssertEqual(settings.vocabularyReplacementRules[1].replace, "GPT")
    }

    func testVocabularyRules_NormalizeCommaSeparatedVariantsAndPreserveFirstGlobalMatch() {
        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: " raycast, reycast , recast, raycast ", replace: "Raycast"),
            VocabularyReplacementRule(find: "recast, recast app, claud", replace: "Claude"),
        ]

        XCTAssertEqual(settings.vocabularyReplacementRules.count, 2)
        XCTAssertEqual(settings.vocabularyReplacementRules[0].find, "raycast, reycast, recast")
        XCTAssertEqual(settings.vocabularyReplacementRules[0].replace, "Raycast")
        XCTAssertEqual(settings.vocabularyReplacementRules[1].find, "recast app, claud")
        XCTAssertEqual(settings.vocabularyReplacementRules[1].replace, "Claude")
    }

    func testResetToDefaults_ClearsVocabularyRules() {
        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: "open ay eye", replace: "OpenAI"),
        ]

        settings.resetToDefaults()

        XCTAssertTrue(settings.vocabularyReplacementRules.isEmpty)
    }
}

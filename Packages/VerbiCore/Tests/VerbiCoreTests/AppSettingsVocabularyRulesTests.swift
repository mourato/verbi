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

    func testVocabularyRules_AreNormalizedAndPreserveConflictingOrigins() {
        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: "  open ay eye  ", replace: " OpenAI "),
            VocabularyReplacementRule(find: "OPEN AY EYE", replace: "SHOULD_NOT_WIN"),
            VocabularyReplacementRule(find: "   ", replace: "ignored"),
            VocabularyReplacementRule(find: "g p t", replace: "GPT")
        ]

        XCTAssertEqual(settings.vocabularyReplacementRules.count, 3)
        XCTAssertEqual(settings.vocabularyReplacementRules[0].find, "open ay eye")
        XCTAssertEqual(settings.vocabularyReplacementRules[0].replace, "OpenAI")
        XCTAssertEqual(settings.vocabularyReplacementRules[1].find, "OPEN AY EYE")
        XCTAssertEqual(settings.vocabularyReplacementRules[1].replace, "SHOULD_NOT_WIN")
        XCTAssertEqual(settings.vocabularyReplacementRules[2].find, "g p t")
        XCTAssertEqual(settings.vocabularyReplacementRules[2].replace, "GPT")
    }

    func testVocabularyRules_NormalizeCommaSeparatedVariantsAndPreserveFirstGlobalMatch() {
        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: " raycast, reycast , recast, raycast ", replace: "Raycast"),
            VocabularyReplacementRule(find: "recast, recast app, claud", replace: "Claude")
        ]

        XCTAssertEqual(settings.vocabularyReplacementRules.count, 2)
        XCTAssertEqual(settings.vocabularyReplacementRules[0].find, "raycast, reycast, recast")
        XCTAssertEqual(settings.vocabularyReplacementRules[0].replace, "Raycast")
        XCTAssertEqual(settings.vocabularyReplacementRules[1].find, "recast, recast app, claud")
        XCTAssertEqual(settings.vocabularyReplacementRules[1].replace, "Claude")
    }

    func testVocabularyRules_PreserveOriginsThatConflictAcrossDestinations() {
        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: "raycast, recast", replace: "Raycast"),
            VocabularyReplacementRule(find: "recast", replace: "Claude")
        ]

        XCTAssertEqual(settings.vocabularyReplacementRules.count, 2)
        XCTAssertEqual(settings.vocabularyReplacementRules[0].find, "raycast, recast")
        XCTAssertEqual(settings.vocabularyReplacementRules[1].find, "recast", "Legacy conflicts stay visible instead of being dropped")
    }

    func testVocabularyRules_ConsolidateVariantsThatShareDestination() {
        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: "raycast", replace: "Raycast"),
            VocabularyReplacementRule(find: "reycast", replace: " Raycast ")
        ]

        XCTAssertEqual(settings.vocabularyReplacementRules.count, 1)
        XCTAssertEqual(settings.vocabularyReplacementRules[0].find, "raycast, reycast")
        XCTAssertEqual(settings.vocabularyReplacementRules[0].replace, "Raycast")
    }

    func testVocabularyRules_KeepCaseSensitiveDestinationsApart() {
        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: "you ess", replace: "US"),
            VocabularyReplacementRule(find: "us", replace: "us")
        ]

        XCTAssertEqual(settings.vocabularyReplacementRules.map(\.replace), ["US", "us"])
    }

    func testVocabularyRules_NormalizeUnicodeAndOuterWhitespace() {
        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: "  cafe\u{301}  ", replace: "  Café  ")
        ]

        XCTAssertEqual(settings.vocabularyReplacementRules.first?.find, "café")
        XCTAssertEqual(settings.vocabularyReplacementRules.first?.replace, "Café")
    }

    func testResetToDefaults_ClearsVocabularyRules() {
        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: "open ay eye", replace: "OpenAI")
        ]

        settings.resetToDefaults()

        XCTAssertTrue(settings.vocabularyReplacementRules.isEmpty)
    }
}

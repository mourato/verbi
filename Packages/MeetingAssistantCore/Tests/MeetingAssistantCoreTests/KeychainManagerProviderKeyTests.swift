@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreInfrastructure
import XCTest

final class KeychainManagerProviderKeyTests: XCTestCase {
    func testGoogleProviderMapsToDedicatedKeychainSlot() {
        XCTAssertEqual(KeychainManager.apiKeyKey(for: .google), .aiAPIKeyGoogle)
    }

    func testOpenAITranscriptionReusesOpenAIProviderKeychainSlot() {
        XCTAssertEqual(KeychainManager.transcriptionAPIKeyKey(for: .openai), KeychainManager.apiKeyKey(for: .openai))
    }

    func testLegacyConsolidatedValuesFillOnlyMissingCurrentValues() {
        var legacy = KeychainManager.ConsolidatedAPIKeys()
        legacy.providerKeys = ["google": "legacy-google", "groq": "legacy-groq"]
        legacy.transcriptionKeys = ["elevenlabs": "legacy-transcription"]

        var current = KeychainManager.ConsolidatedAPIKeys()
        current.providerKeys = ["google": "current-google"]

        let merged = KeychainManager.mergeMissingValues(from: legacy, into: current)

        XCTAssertEqual(merged.providerKeys["google"], "current-google")
        XCTAssertEqual(merged.providerKeys["groq"], "legacy-groq")
        XCTAssertEqual(merged.transcriptionKeys["elevenlabs"], "legacy-transcription")
    }
}

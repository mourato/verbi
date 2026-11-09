@testable import VerbiCoreAI
import VerbiCoreDomain
import VerbiCoreInfrastructure
import XCTest

final class ElevenLabsVocabularyRequestTests: XCTestCase {
    /// The provider-level capability mapping must hold for every known
    /// ElevenLabs model, including the legacy `scribe_v1` selection: each
    /// request carries repeated `keyterms` fields with the documented caps.
    /// Proves `TranscriptionProvider.vocabularyHelper` cannot diverge per model.
    func testMultipartBody_CarriesKeytermsForEveryKnownModel() {
        for modelID in TranscriptionProvider.elevenLabsKnownModelIDs {
            let long = String(repeating: "a", count: 51)
            let body = ElevenLabsTranscriptionClient.multipartBody(
                boundary: "Bound",
                fileData: Data("audio".utf8),
                fileName: "clip.wav",
                modelID: modelID,
                inputLanguageCode: "en",
                vocabularyKeyterms: ["SwiftUI", long, "Metal"]
            )
            let text = String(bytes: body, encoding: .utf8) ?? ""

            let keytermFieldCount = text.components(separatedBy: "name=\"keyterms\"").count - 1
            XCTAssertEqual(keytermFieldCount, 2, "model \(modelID)")
            XCTAssertTrue(text.contains("SwiftUI"), "model \(modelID)")
            XCTAssertTrue(text.contains("Metal"), "model \(modelID)")
            XCTAssertFalse(text.contains(long), "model \(modelID) sent over-length keyterm")
        }
    }

    func testMultipartBody_IncludesRepeatedKeytermsFields() {
        let body = ElevenLabsTranscriptionClient.multipartBody(
            boundary: "Bound",
            fileData: Data("audio".utf8),
            fileName: "clip.wav",
            modelID: "scribe_v2",
            inputLanguageCode: "en",
            vocabularyKeyterms: ["SwiftUI", "Metal"],
        )
        let text = String(bytes: body, encoding: .utf8) ?? ""

        XCTAssertTrue(text.contains("name=\"keyterms\""))
        XCTAssertTrue(text.contains("SwiftUI"))
        XCTAssertTrue(text.contains("Metal"))
        XCTAssertFalse(text.contains("name=\"custom_prompt\""))
        XCTAssertFalse(text.contains("name=\"prompt\""))

        let keytermFieldCount = text.components(separatedBy: "name=\"keyterms\"").count - 1
        XCTAssertEqual(keytermFieldCount, 2)
    }

    func testMultipartBody_OmitsKeytermsWhenEmpty() {
        let body = ElevenLabsTranscriptionClient.multipartBody(
            boundary: "Bound",
            fileData: Data("audio".utf8),
            fileName: "clip.wav",
            modelID: "scribe_v2",
            inputLanguageCode: nil,
            vocabularyKeyterms: [],
        )
        let text = String(bytes: body, encoding: .utf8) ?? ""

        XCTAssertFalse(text.contains("name=\"keyterms\""))
        XCTAssertFalse(text.contains("name=\"custom_prompt\""))
    }

    func testMultipartBody_SkipsInvalidKeytermsAtWireBoundary() {
        let long = String(repeating: "a", count: 51)
        let body = ElevenLabsTranscriptionClient.multipartBody(
            boundary: "bound",
            fileData: Data("audio".utf8),
            fileName: "clip.wav",
            modelID: "scribe_v2",
            inputLanguageCode: nil,
            vocabularyKeyterms: ["SwiftUI", long, "bad<term>", "Metal"],
        )
        let text = String(bytes: body, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("SwiftUI"))
        XCTAssertTrue(text.contains("Metal"))
        XCTAssertFalse(text.contains(long))
        XCTAssertFalse(text.contains("bad<term>"))
        let keytermFieldCount = text.components(separatedBy: "name=\"keyterms\"").count - 1
        XCTAssertEqual(keytermFieldCount, 2)
    }
}

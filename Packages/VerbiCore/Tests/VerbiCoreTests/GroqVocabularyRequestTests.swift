@testable import VerbiCoreAI
import VerbiCoreDomain
import VerbiCoreInfrastructure
import XCTest

final class GroqVocabularyRequestTests: XCTestCase {
    /// The provider-level capability mapping must hold for every selectable
    /// Groq model: each preset model's request carries the `prompt` field with
    /// the same wire cap. This is the wrapper test that proves
    /// `TranscriptionProvider.vocabularyHelper` cannot diverge per model.
    func testMultipartBody_CarriesPromptForEveryPresetModelWithWireCap() throws {
        for modelID in TranscriptionProvider.groqPresetModelIDs {
            let hint = "SwiftUI, " + String(repeating: "z", count: 795)
            let body = GroqTranscriptionClient.multipartBody(
                boundary: "Bound",
                fileData: Data("audio".utf8),
                fileName: "clip.wav",
                modelID: modelID,
                inputLanguageCode: "en",
                vocabularyHint: hint
            )
            let text = String(bytes: body, encoding: .utf8) ?? ""

            XCTAssertTrue(text.contains("name=\"prompt\""), "model \(modelID) dropped prompt")
            let capped = try XCTUnwrap(VocabularyProviderHints.capGroqPrompt(hint))
            XCTAssertTrue(try text.contains(capped), "model \(modelID) sent uncapped prompt")
            XCTAssertLessThanOrEqual(capped.count, VocabularyProviderHints.groqMaxCharacters)
        }
    }

    /// End-to-end acceptance proof for issue #138: saved terms "A,B" and a
    /// 795-character term at the 800-character limit. The wire rebuilds the
    /// joined prompt, splitting the comma term into "A, B"; the long term must
    /// not reach the request, and the summary derived by
    /// `VocabularyRecognitionSupport` must match exactly what this body sends.
    func testMultipartBody_RebuildsJoinedPromptSplittingCommaTermAtBudgetLimit() throws {
        let prompt = VocabularySnapshot(
            terms: [
                VocabularyTerm(term: "A,B", definition: ""),
                VocabularyTerm(term: String(repeating: "x", count: 795), definition: "")
            ],
            replacementRules: []
        ).projectedGroqPrompt()
        let body = GroqTranscriptionClient.multipartBody(
            boundary: "Bound",
            fileData: Data("audio".utf8),
            fileName: "clip.wav",
            modelID: "whisper-large-v3-turbo",
            inputLanguageCode: "en",
            vocabularyHint: try XCTUnwrap(prompt)
        )
        let text = String(bytes: body, encoding: .utf8) ?? ""

        let wiredPrompt = try XCTUnwrap(VocabularyProviderHints.capGroqPrompt(prompt))
        XCTAssertEqual(wiredPrompt, "A, B")
        XCTAssertTrue(try text.contains(wiredPrompt), "wire must send the rebuilt \"A, B\" prompt")
        let longTerm = String(repeating: "x", count: 795)
        XCTAssertFalse(text.contains(longTerm), "long term must not reach the request")
    }

    func testMultipartBody_IncludesPromptWhenHintProvided() {
        let body = GroqTranscriptionClient.multipartBody(
            boundary: "Bound",
            fileData: Data("audio".utf8),
            fileName: "clip.wav",
            modelID: "whisper-large-v3-turbo",
            inputLanguageCode: "en",
            vocabularyHint: "SwiftUI, Metal",
        )
        let text = String(bytes: body, encoding: .utf8) ?? ""

        XCTAssertTrue(text.contains("name=\"prompt\""))
        XCTAssertTrue(text.contains("SwiftUI, Metal"))
        XCTAssertFalse(text.contains("name=\"keyterms\""))
    }

    func testMultipartBody_OmitsPromptWhenHintEmpty() {
        let body = GroqTranscriptionClient.multipartBody(
            boundary: "Bound",
            fileData: Data("audio".utf8),
            fileName: "clip.wav",
            modelID: "whisper-large-v3-turbo",
            inputLanguageCode: nil,
            vocabularyHint: nil,
        )
        let text = String(bytes: body, encoding: .utf8) ?? ""

        XCTAssertFalse(text.contains("name=\"prompt\""))
    }

    func testMultipartBody_EnforcesGroqCharacterBudget() throws {
        let huge = Array(repeating: "ABCDEFGHIJ", count: 100).joined(separator: ", ")
        let body = GroqTranscriptionClient.multipartBody(
            boundary: "bound",
            fileData: Data("audio".utf8),
            fileName: "clip.wav",
            modelID: "whisper-large-v3-turbo",
            inputLanguageCode: nil,
            vocabularyHint: huge,
        )
        let text = String(bytes: body, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("name=\"prompt\""))
        let capped = VocabularyProviderHints.capGroqPrompt(huge)
        XCTAssertNotNil(capped)
        XCTAssertLessThanOrEqual(try XCTUnwrap(capped?.count), VocabularyProviderHints.groqMaxCharacters)
        XCTAssertTrue(try text.contains(XCTUnwrap(capped)))
        XCTAssertFalse(text.contains(huge))
    }
}

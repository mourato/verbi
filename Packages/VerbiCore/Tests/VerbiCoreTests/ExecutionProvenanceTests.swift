@testable import VerbiCore
import XCTest

final class ExecutionProvenanceTests: XCTestCase {
    func testCodableRoundTripPreservesKnownExecutionInputs() throws {
        let request = DomainTranscriptionRequestConfiguration(
            providerID: "groq",
            modelID: "whisper-large-v3",
            inputLanguageCode: "pt"
        )
        let provenance = ExecutionProvenance(
            transcriptionRequest: request,
            vocabularySnapshot: VocabularySnapshot.empty,
            transcriptionModelIdentity: ModelPerformanceModelIdentity(
                providerID: "groq",
                providerDisplayName: "Groq",
                modelID: "whisper-large-v3",
                modelDisplayName: "Whisper",
                runtimeKind: .remote
            ),
            postProcessingSelection: DomainPostProcessingSelection(
                providerID: "openai",
                modelID: "gpt-4o-mini",
                registrationID: nil
            ),
            kernelMode: .meeting,
            usedStructuredPostProcessing: true,
            skipPostProcessing: true
        )

        let data = try JSONEncoder().encode(provenance)
        let decoded = try JSONDecoder().decode(ExecutionProvenance.self, from: data)
        XCTAssertEqual(decoded, provenance)
        XCTAssertTrue(decoded.skipPostProcessing)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "skipPostProcessingOverride")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        XCTAssertFalse(try JSONDecoder().decode(ExecutionProvenance.self, from: legacyData).skipPostProcessing)
    }

    func testMissingOptionalProvenanceDecodesAsUnavailable() throws {
        let data = try JSONSerialization.data(withJSONObject: ["text": "legacy"])
        struct Legacy: Codable { let text: String
            let provenance: ExecutionProvenance?
        }
        XCTAssertNil(try JSONDecoder().decode(Legacy.self, from: data).provenance)
    }
}

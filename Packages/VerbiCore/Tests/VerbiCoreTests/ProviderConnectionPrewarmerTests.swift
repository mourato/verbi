import Foundation
@testable import VerbiCoreAI
import XCTest

final class ProviderConnectionPrewarmerTests: XCTestCase {
    func testOriginDropsPathSoTheProbeHitsOnlyTheHostRoot() {
        XCTAssertEqual(
            ProviderConnectionPrewarmer.origin(of: "https://api.groq.com/openai/v1")?.absoluteString,
            "https://api.groq.com/"
        )
    }

    func testOriginKeepsAnExplicitPort() {
        XCTAssertEqual(
            ProviderConnectionPrewarmer.origin(of: "https://llm.example.com:8443/v1")?.absoluteString,
            "https://llm.example.com:8443/"
        )
    }

    func testOriginSkipsPlainHTTPAndInvalidValues() {
        XCTAssertNil(ProviderConnectionPrewarmer.origin(of: "http://localhost:11434/v1"))
        XCTAssertNil(ProviderConnectionPrewarmer.origin(of: ""))
    }
}

@testable import VerbiCore
import XCTest

@MainActor
final class AssistantRaycastIntegrationServiceTests: XCTestCase {
    func testValidateDeepLink_WithRaycastScheme_ReturnsValid() {
        let service = makeService()

        let result = service.validateDeepLink("raycast://extensions/raycast/raycast-ai/ai-chat")

        XCTAssertEqual(result, .valid)
    }

    func testValidateDeepLink_WithExtensionsCommandShape_ReturnsValid() {
        let service = makeService()

        let result = service.validateDeepLink("raycast://extensions/raycast/file-search/search-files")

        XCTAssertEqual(result, .valid)
    }

    func testValidateDeepLink_WithInvalidScheme_ReturnsInvalid() {
        let service = makeService()

        let result = service.validateDeepLink("https://raycast.com")

        XCTAssertEqual(result, .invalid)
    }

    func testValidateDeepLink_WithUnsupportedRaycastHost_ReturnsInvalid() {
        let service = makeService()

        let result = service.validateDeepLink("raycast://unknown-host/anything")

        XCTAssertEqual(result, .invalid)
    }

    func testValidateDeepLink_WithExtensionsMissingCommand_ReturnsInvalid() {
        let service = makeService()

        let result = service.validateDeepLink("raycast://extensions/raycast/file-search")

        XCTAssertEqual(result, .invalid)
    }

    func testDispatch_WithValidCommand_OpensDeepLinkWithCommandPayloadKeys() throws {
        var openedURLs: [URL] = []
        let service = makeService(
            openURL: { url in
                openedURLs.append(url)
                return true
            },
        )

        let result = try service.dispatch(
            command: "hello world",
            baseDeepLink: "raycast://extensions/raycast/raycast-ai/ai-chat",
        )

        XCTAssertEqual(result, .openedDeepLink)
        XCTAssertEqual(openedURLs.count, 1)

        let components = try XCTUnwrap(URLComponents(url: openedURLs[0], resolvingAgainstBaseURL: false))
        let queryItems = components.queryItems ?? []
        XCTAssertEqual(queryItems.first(where: { $0.name == "fallbackText" })?.value, "hello world")
        XCTAssertEqual(queryItems.first(where: { $0.name == "text" })?.value, "hello world")
        XCTAssertEqual(queryItems.first(where: { $0.name == "query" })?.value, "hello world")
        XCTAssertEqual(queryItems.first(where: { $0.name == "prompt" })?.value, "hello world")
    }

    func testDispatch_WithExistingPayload_ReplacesOldValues() throws {
        var openedURL: URL?
        let service = makeService(
            openURL: { url in
                openedURL = url
                return true
            },
        )

        let result = try service.dispatch(
            command: "new value",
            baseDeepLink: "raycast://extensions/raycast/raycast-ai/ai-chat?fallbackText=old&query=old",
        )

        XCTAssertEqual(result, .openedDeepLink)
        let components = try XCTUnwrap(try URLComponents(url: XCTUnwrap(openedURL), resolvingAgainstBaseURL: false))
        let fallbackValues = components.queryItems?
            .filter { $0.name == "fallbackText" || $0.name == "query" }
            .compactMap(\.value) ?? []
        XCTAssertEqual(fallbackValues, ["new value", "new value"])
    }

    func testDispatch_WithInvalidDeepLink_ThrowsInvalidDeepLinkError() {
        let service = makeService()

        XCTAssertThrowsError(
            try service.dispatch(command: "test", baseDeepLink: "invalid-link"),
        ) { error in
            XCTAssertEqual(error as? AssistantIntegrationDispatchError, .invalidDeepLink)
        }
    }

    func testDispatch_WithUnsupportedHost_ThrowsInvalidDeepLinkError() {
        let service = makeService()

        XCTAssertThrowsError(
            try service.dispatch(command: "test", baseDeepLink: "raycast://unknown-host/ask"),
        ) { error in
            XCTAssertEqual(error as? AssistantIntegrationDispatchError, .invalidDeepLink)
        }
    }

    func testDispatch_WhenURLExceedsLimit_OpensDeepLinkWithInlinePayload() throws {
        var openedURLs: [URL] = []
        var copiedText: String?
        let service = makeService(
            openURL: { url in
                openedURLs.append(url)
                return true
            },
            copyToClipboard: { text in
                copiedText = text
            },
            maxDeepLinkLength: 40,
        )

        let result = try service.dispatch(
            command: String(repeating: "x", count: 120),
            baseDeepLink: "raycast://extensions/raycast/raycast-ai/ai-chat",
        )

        XCTAssertEqual(result, .openedDeepLink)
        XCTAssertNil(copiedText)
        XCTAssertEqual(openedURLs.count, 1)

        let components = try XCTUnwrap(URLComponents(url: openedURLs[0], resolvingAgainstBaseURL: false))
        let dispatchValues = components.queryItems?
            .filter { ["fallbackText", "text", "query", "prompt"].contains($0.name) }
            .compactMap(\.value) ?? []
        XCTAssertEqual(dispatchValues, Array(repeating: String(repeating: "x", count: 120), count: 4))
    }

    private func makeService(
        openURL: @escaping (URL) -> Bool = { _ in true },
        copyToClipboard: @escaping (String) -> Void = { _ in },
        maxDeepLinkLength: Int = 3_800,
    ) -> AssistantRaycastIntegrationService {
        AssistantRaycastIntegrationService(
            openURL: openURL,
            copyToClipboard: copyToClipboard,
            maxDeepLinkLength: maxDeepLinkLength,
        )
    }
}

@testable import VerbiCore
import XCTest

final class TranscriptionsNavigationHistoryTests: XCTestCase {
    func testInitialStateStartsAtList() {
        let history = TranscriptionsNavigationHistory()

        XCTAssertEqual(history.currentRoute, .list)
        XCTAssertFalse(history.canGoBack)
        XCTAssertFalse(history.canGoForward)
    }

    func testPushAndNavigateBackAndForward() {
        let firstID = UUID()
        let secondID = UUID()
        var history = TranscriptionsNavigationHistory()

        history.push(.conversation(firstID))
        history.push(.conversation(secondID))

        XCTAssertEqual(history.currentRoute, .conversation(secondID))
        XCTAssertTrue(history.canGoBack)
        XCTAssertFalse(history.canGoForward)

        _ = history.goBack()
        XCTAssertEqual(history.currentRoute, .conversation(firstID))
        XCTAssertTrue(history.canGoBack)
        XCTAssertTrue(history.canGoForward)

        _ = history.goBack()
        XCTAssertEqual(history.currentRoute, .list)
        XCTAssertFalse(history.canGoBack)
        XCTAssertTrue(history.canGoForward)

        _ = history.goForward()
        XCTAssertEqual(history.currentRoute, .conversation(firstID))
    }

    func testPushFromMiddleDropsForwardHistory() {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        var history = TranscriptionsNavigationHistory()

        history.push(.conversation(firstID))
        history.push(.conversation(secondID))
        _ = history.goBack()

        history.push(.conversation(thirdID))

        XCTAssertEqual(history.currentRoute, .conversation(thirdID))
        XCTAssertFalse(history.canGoForward)
    }

    func testSanitizeRemovesInvalidRoutes() {
        let validID = UUID()
        let removedID = UUID()
        var history = TranscriptionsNavigationHistory()

        history.push(.conversation(validID))
        history.push(.conversation(removedID))

        history.sanitize(validConversationIDs: [validID])

        XCTAssertEqual(history.currentRoute, .conversation(validID))
        XCTAssertTrue(history.canGoBack)
        XCTAssertFalse(history.canGoForward)
    }

    func testSanitizeResetsToListWhenEverythingIsRemoved() {
        let removedID = UUID()
        var history = TranscriptionsNavigationHistory(initialRoute: .conversation(removedID))

        history.sanitize(validConversationIDs: [])

        XCTAssertEqual(history.currentRoute, .list)
        XCTAssertFalse(history.canGoBack)
        XCTAssertFalse(history.canGoForward)
    }
}

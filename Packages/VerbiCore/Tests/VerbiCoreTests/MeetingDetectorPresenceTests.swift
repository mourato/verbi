import Foundation
@testable import VerbiCoreDomain
@testable import VerbiCoreInfrastructure
import XCTest

@MainActor
final class MeetingDetectorPresenceTests: XCTestCase {
    private let gracePeriod: TimeInterval = 30
    private let clock = TestClock()
    private var resolver: MockCaptureContextResolver!
    private var media: StubMediaActivityProvider!
    private var detector: MeetingDetector!

    override func setUp() {
        super.setUp()
        resolver = MockCaptureContextResolver()
        media = StubMediaActivityProvider()
        detector = MeetingDetector(
            captureContextResolver: resolver,
            mediaActivityProvider: media,
            detectionLossGracePeriod: gracePeriod,
            now: { [clock] in clock.now }
        )
    }

    func testBriefLossKeepsMeetingUntilGracePeriodEnds() {
        let zoom = context(app: .zoom, bundleID: "us.zoom.xos")
        media.isActive = true
        resolver.detectedMeetingCandidate = zoom
        detector.checkForMeetings()
        XCTAssertEqual(detector.detectedContext, zoom)

        resolver.detectedMeetingCandidate = nil
        detector.checkForMeetings()
        clock.advance(gracePeriod - 1)
        detector.checkForMeetings()
        XCTAssertEqual(detector.detectedContext, zoom)

        clock.advance(1)
        detector.checkForMeetings()
        XCTAssertNil(detector.detectedContext)
        XCTAssertNil(detector.detectedMeeting)
    }

    func testReturningSignalResetsGracePeriod() {
        let zoom = context(app: .zoom, bundleID: "us.zoom.xos")
        media.isActive = true
        resolver.detectedMeetingCandidate = zoom
        detector.checkForMeetings()

        resolver.detectedMeetingCandidate = nil
        detector.checkForMeetings()
        clock.advance(gracePeriod - 1)
        resolver.detectedMeetingCandidate = zoom
        detector.checkForMeetings()

        resolver.detectedMeetingCandidate = nil
        clock.advance(gracePeriod - 1)
        detector.checkForMeetings()
        XCTAssertEqual(detector.detectedContext, zoom)
    }

    func testRunningAppWithActiveMediaKeepsMeetingWhenUrlNoLongerMatches() {
        // Finder always runs, so it stands in for a browser whose meeting tab lost focus.
        let meet = context(app: .googleMeet, bundleID: "com.apple.finder", url: "https://meet.google.com/abc-defg-hij")
        media.isActive = true
        resolver.detectedMeetingCandidate = meet
        detector.checkForMeetings()

        resolver.detectedMeetingCandidate = nil
        clock.advance(gracePeriod * 4)
        detector.checkForMeetings()
        XCTAssertEqual(detector.detectedContext, meet)

        media.isActive = false
        detector.checkForMeetings()
        clock.advance(gracePeriod)
        detector.checkForMeetings()
        XCTAssertNil(detector.detectedContext)
    }

    func testSameMeetingWithNewUrlDoesNotReplaceDetectedContext() {
        let first = context(app: .googleMeet, bundleID: "com.google.Chrome", url: "https://meet.google.com/abc-defg-hij")
        let sameMeetingNewURL = context(
            app: .googleMeet,
            bundleID: "com.google.chrome",
            url: "https://meet.google.com/abc-defg-hij?authuser=1"
        )
        var published: [ResolvedCaptureContext?] = []
        let cancellable = detector.$detectedContext.dropFirst().sink { published.append($0) }
        defer { cancellable.cancel() }
        media.isActive = true

        resolver.detectedMeetingCandidate = first
        detector.checkForMeetings()
        resolver.detectedMeetingCandidate = sameMeetingNewURL
        detector.checkForMeetings()

        XCTAssertEqual(published, [first])
    }

    func testSameMeetingIgnoresUrlAndDisplayNameButNotApp() {
        let meet = context(app: .googleMeet, bundleID: "com.google.Chrome", url: "https://meet.google.com/a", name: "Chrome")
        XCTAssertTrue(meet.isSameMeeting(as: context(
            app: .googleMeet,
            bundleID: "COM.GOOGLE.CHROME",
            url: "https://meet.google.com/a?x=1",
            name: "Google Chrome"
        )))
        XCTAssertFalse(meet.isSameMeeting(as: context(app: .zoom, bundleID: "com.google.Chrome")))
        XCTAssertFalse(meet.isSameMeeting(as: context(app: .googleMeet, bundleID: "com.apple.Safari")))
    }

    private func context(
        app: CaptureOrigin,
        bundleID: String,
        url: String? = nil,
        name: String? = nil
    ) -> ResolvedCaptureContext {
        ResolvedCaptureContext(
            purpose: .meeting,
            meetingApp: app,
            appBundleIdentifier: bundleID,
            appDisplayName: name,
            activeBrowserURL: url.flatMap(URL.init(string:)),
            isKnownMeetingCandidate: true
        )
    }
}

@MainActor
private final class TestClock {
    private(set) var now = Date(timeIntervalSince1970: 1_000_000)

    func advance(_ interval: TimeInterval) {
        now.addTimeInterval(interval)
    }
}

@MainActor
private final class StubMediaActivityProvider: MeetingMediaActivityProviding {
    var isActive = false

    func currentActivity() -> MeetingMediaActivity {
        MeetingMediaActivity(microphoneInUseByAnotherApplication: isActive)
    }
}

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
            now: { [clock] in clock.now },
            runningApplications: { [] }
        )
    }

    func testBriefLossKeepsMeetingUntilGracePeriodEndsButWithoutLiveSignal() {
        let zoom = context(app: .zoom, bundleID: "us.zoom.xos")
        media.callOwners = ["us.zoom.xos"]
        resolver.detectedMeetingCandidate = zoom
        detector.checkForMeetings()
        XCTAssertEqual(detector.detectedContext, zoom)
        XCTAssertTrue(detector.isMeetingSignalPresent)

        resolver.detectedMeetingCandidate = nil
        media.callOwners = []
        detector.checkForMeetings()
        clock.advance(gracePeriod - 1)
        detector.checkForMeetings()
        XCTAssertEqual(detector.detectedContext, zoom)
        XCTAssertFalse(detector.isMeetingSignalPresent, "A meeting in its grace period must not auto-start a recording")

        clock.advance(1)
        detector.checkForMeetings()
        XCTAssertNil(detector.detectedContext)
        XCTAssertNil(detector.detectedMeeting)
    }

    func testReturningSignalResetsGracePeriod() {
        let zoom = context(app: .zoom, bundleID: "us.zoom.xos")
        resolver.detectedMeetingCandidate = zoom
        detector.checkForMeetings()

        resolver.detectedMeetingCandidate = nil
        detector.checkForMeetings()
        clock.advance(gracePeriod - 1)
        resolver.detectedMeetingCandidate = zoom
        detector.checkForMeetings()
        XCTAssertTrue(detector.isMeetingSignalPresent)

        resolver.detectedMeetingCandidate = nil
        clock.advance(gracePeriod - 1)
        detector.checkForMeetings()
        XCTAssertEqual(detector.detectedContext, zoom)
    }

    func testBrowserHelperHoldingMicrophoneKeepsMeetingAfterTabSwitch() {
        let meet = webMeet(path: "/abc-defg-hij")
        resolver.detectedMeetingCandidate = meet
        detector.checkForMeetings()

        // The tab lost focus, so the URL no longer matches; Chrome's helper still holds the microphone.
        resolver.detectedMeetingCandidate = nil
        media.callOwners = ["com.google.Chrome.helper"]
        clock.advance(gracePeriod * 4)
        detector.checkForMeetings()
        XCTAssertEqual(detector.detectedContext, meet)
        XCTAssertTrue(detector.isMeetingSignalPresent)
    }

    func testAnotherAppUsingMicrophoneDoesNotKeepEndedMeetingAlive() {
        let meet = webMeet(path: "/abc-defg-hij")
        resolver.detectedMeetingCandidate = meet
        detector.checkForMeetings()

        resolver.detectedMeetingCandidate = nil
        media.callOwners = ["com.example.dictation"]
        detector.checkForMeetings()
        clock.advance(gracePeriod)
        detector.checkForMeetings()
        XCTAssertNil(detector.detectedContext)
    }

    func testDifferentMeetingReplacesDetectedMeetingImmediately() {
        let meet = webMeet(path: "/abc-defg-hij")
        let zoom = context(app: .zoom, bundleID: "us.zoom.xos")
        resolver.detectedMeetingCandidate = meet
        detector.checkForMeetings()

        media.callOwners = ["com.google.Chrome.helper", "us.zoom.xos"]
        resolver.detectedMeetingCandidate = zoom
        detector.checkForMeetings()
        XCTAssertEqual(detector.detectedContext, zoom)

        let nextRoom = webMeet(path: "/xyz-wxyz-xyz")
        resolver.detectedMeetingCandidate = nextRoom
        detector.checkForMeetings()
        XCTAssertEqual(detector.detectedContext, nextRoom)
    }

    func testRunningAppCandidateDoesNotReplaceMeetingAfterTabSwitch() {
        let meet = webMeet(path: "/abc-defg-hij")
        resolver.detectedMeetingCandidate = meet
        media.callOwners = ["com.google.Chrome.helper"]
        detector.checkForMeetings()

        // After a tab switch the resolver falls back to a monitored app that is merely running.
        resolver.detectedMeetingCandidate = context(app: .slack, bundleID: "com.tinyspeck.slackmacgap")
        detector.checkForMeetings()
        XCTAssertEqual(detector.detectedContext, meet)
    }

    func testOtherMeetRoomInSameBrowserDoesNotReplaceOngoingCall() {
        let meet = webMeet(path: "/abc-defg-hij")
        resolver.detectedMeetingCandidate = meet
        media.callOwners = ["com.google.Chrome.helper"]
        detector.checkForMeetings()

        resolver.detectedMeetingCandidate = webMeet(path: "/")
        detector.checkForMeetings()
        XCTAssertEqual(detector.detectedContext, meet)

        // Once the call ends, the next room is a new meeting.
        media.callOwners = []
        let nextRoom = webMeet(path: "/xyz-wxyz-xyz")
        resolver.detectedMeetingCandidate = nextRoom
        detector.checkForMeetings()
        XCTAssertEqual(detector.detectedContext, nextRoom)
    }

    func testSafariMeetingStaysPresentWhileWebKitHoldsMicrophone() {
        let safariMeet = context(app: .googleMeet, bundleID: "com.apple.Safari")
        resolver.detectedMeetingCandidate = safariMeet
        detector.checkForMeetings()

        resolver.detectedMeetingCandidate = nil
        media.callOwners = ["com.apple.WebKit.GPU"]
        clock.advance(gracePeriod * 2)
        detector.checkForMeetings()
        XCTAssertEqual(detector.detectedContext, safariMeet)
    }

    func testSameMeetingWithNewQueryDoesNotReplaceDetectedContext() {
        let first = webMeet(path: "/abc-defg-hij")
        let sameRoom = webMeet(path: "/abc-defg-hij", query: "?authuser=1")
        var published: [ResolvedCaptureContext?] = []
        let cancellable = detector.$detectedContext.dropFirst().sink { published.append($0) }
        defer { cancellable.cancel() }

        resolver.detectedMeetingCandidate = first
        detector.checkForMeetings()
        resolver.detectedMeetingCandidate = sameRoom
        detector.checkForMeetings()

        XCTAssertEqual(published, [first])
    }

    func testSameMeetingComparesAppBundleAndRoomOnly() {
        let meet = webMeet(path: "/abc-defg-hij", name: "Chrome")
        XCTAssertTrue(meet.isSameMeeting(as: webMeet(path: "/ABC-DEFG-HIJ", query: "?x=1", name: "Google Chrome")))
        XCTAssertFalse(meet.isSameMeeting(as: webMeet(path: "/other-room")))
        XCTAssertFalse(meet.isSameMeeting(as: context(app: .zoom, bundleID: "com.google.Chrome")))
        XCTAssertFalse(meet.isSameMeeting(as: context(app: .googleMeet, bundleID: "com.apple.Safari")))
    }

    private let meetTargetID = UUID()

    private func webMeet(path: String, query: String = "", name: String? = nil) -> ResolvedCaptureContext {
        ResolvedCaptureContext(
            purpose: .meeting,
            meetingApp: .googleMeet,
            appBundleIdentifier: "com.google.Chrome",
            appDisplayName: name,
            activeBrowserURL: URL(string: "https://meet.google.com\(path)\(query)"),
            matchedWebMeetingTargetID: meetTargetID,
            isKnownMeetingCandidate: true
        )
    }

    private func context(app: CaptureOrigin, bundleID: String) -> ResolvedCaptureContext {
        ResolvedCaptureContext(
            purpose: .meeting,
            meetingApp: app,
            appBundleIdentifier: bundleID,
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

/// Reports which processes hold the microphone, with resolved attribution.
@MainActor
private final class StubMediaActivityProvider: MeetingMediaActivityProviding {
    var callOwners: [String] = []

    func currentActivity() -> MeetingMediaActivity {
        MeetingMediaActivity(
            microphoneInUseByAnotherApplication: !callOwners.isEmpty,
            signals: MeetingDetectionSignals(
                microphoneOwnerBundleIdentifier: callOwners.first,
                attribution: callOwners.isEmpty ? .unavailable : .resolved,
                activeCallBundleIdentifiers: callOwners
            )
        )
    }
}

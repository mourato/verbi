import SwiftUI
@testable import VerbiCoreUI
import XCTest

final class AppleMotionTests: XCTestCase {
    func testSpringSpecsExposeNamedMotionPolicy() {
        XCTAssertEqual(AppleMotion.defaultSpringSpec, .init(response: 0.35, dampingFraction: 1.0))
        XCTAssertEqual(AppleMotion.interactiveSpringSpec, .init(response: 0.3, dampingFraction: 0.85))
        XCTAssertEqual(AppleMotion.pressSpringSpec, .init(response: 0.15, dampingFraction: 1.0))
    }

    func testTransitionStyleUsesOpacityForReduceMotion() {
        XCTAssertEqual(
            AppleMotion.transitionStyle(reduceMotion: true, edge: .top),
            .opacity,
        )
    }

    func testTransitionStyleUsesMoveAndOpacityForDefaultMotion() {
        XCTAssertEqual(
            AppleMotion.transitionStyle(reduceMotion: false, edge: .bottom),
            .moveAndOpacity(edge: .bottom),
        )
    }

    func testReduceMotionAnimationCanDisableAnimationWhenRequested() {
        XCTAssertNil(
            AppleMotion.animation(
                reduceMotion: true,
                reduceMotionAnimation: .none,
            ),
        )
    }

    func testDisclosureAndReduceMotionFadeDurationsStayIndependent() {
        XCTAssertEqual(AppleMotion.disclosureDuration, 0.2)
        XCTAssertEqual(AppleMotion.reduceMotionFadeDuration, 0.2)
        XCTAssertEqual(AppleMotion.disclosureDuration(reduceMotion: false), AppleMotion.disclosureDuration)
        XCTAssertEqual(AppleMotion.disclosureDuration(reduceMotion: true), AppleMotion.reduceMotionFadeDuration)
    }

    func testDisclosureAnimationUsesDurationPolicyForReduceMotion() {
        XCTAssertNotNil(AppleMotion.disclosureAnimation(reduceMotion: false))
        XCTAssertNotNil(AppleMotion.disclosureAnimation(reduceMotion: true))
        XCTAssertEqual(
            AppleMotion.disclosureDuration(reduceMotion: true),
            AppleMotion.reduceMotionFadeDuration,
        )
        XCTAssertEqual(
            AppleMotion.disclosureDuration(reduceMotion: false),
            AppleMotion.disclosureDuration,
        )
    }

    func testRecordingIndicatorHoverConstantsStayStable() {
        XCTAssertEqual(AppDesignSystem.Layout.recordingIndicatorHoverEnterResponse, 0.22)
        XCTAssertEqual(AppDesignSystem.Layout.recordingIndicatorHoverEnterDamping, 0.86)
    }
}

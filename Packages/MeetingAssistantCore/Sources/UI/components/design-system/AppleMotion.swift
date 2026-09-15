import SwiftUI

public enum AppleMotion {
    public enum SpringKind: Equatable, Sendable {
        case `default`
        case interactive
        case press
    }

    public struct SpringSpec: Equatable, Sendable {
        public let response: Double
        public let dampingFraction: Double
    }

    public enum TransitionStyle: Equatable, Sendable {
        case opacity
        case moveAndOpacity(edge: Edge)
    }

    public enum ReduceMotionAnimation: Equatable, Sendable {
        case fade
        case none
    }

    public static let defaultSpringSpec = SpringSpec(response: 0.35, dampingFraction: 1.0)
    public static let interactiveSpringSpec = SpringSpec(response: 0.3, dampingFraction: 0.85)
    public static let pressSpringSpec = SpringSpec(response: 0.15, dampingFraction: 1.0)

    public static var defaultSpring: Animation {
        animation(for: defaultSpringSpec)
    }

    public static var interactiveSpring: Animation {
        animation(for: interactiveSpringSpec)
    }

    public static var pressSpring: Animation {
        animation(for: pressSpringSpec)
    }

    /// Short easeInOut for Form/layout height disclosure. Gesture-driven surfaces keep springs.
    /// Kept independent from `reduceMotionFadeDuration` so disclosure tuning cannot retune global RM fades.
    public static let disclosureDuration: TimeInterval = 0.2

    /// Duration for Reduce Motion opacity cross-fades across the app.
    public static let reduceMotionFadeDuration: TimeInterval = 0.2

    public static var disclosureAnimation: Animation {
        .easeInOut(duration: disclosureDuration)
    }

    public static var reduceMotionFade: Animation {
        .easeInOut(duration: reduceMotionFadeDuration)
    }

    /// Duration selected by `disclosureAnimation(reduceMotion:)`.
    public static func disclosureDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reduceMotionFadeDuration : disclosureDuration
    }

    public static func disclosureAnimation(reduceMotion: Bool) -> Animation? {
        .easeInOut(duration: disclosureDuration(reduceMotion: reduceMotion))
    }

    public static func springSpec(for kind: SpringKind) -> SpringSpec {
        switch kind {
        case .default:
            defaultSpringSpec
        case .interactive:
            interactiveSpringSpec
        case .press:
            pressSpringSpec
        }
    }

    public static func animation(
        reduceMotion: Bool,
        kind: SpringKind = .default,
        reduceMotionAnimation: ReduceMotionAnimation = .fade
    ) -> Animation? {
        guard reduceMotion else {
            return animation(for: springSpec(for: kind))
        }

        switch reduceMotionAnimation {
        case .fade:
            return reduceMotionFade
        case .none:
            return nil
        }
    }

    public static func transitionStyle(
        reduceMotion: Bool,
        edge: Edge = .top
    ) -> TransitionStyle {
        reduceMotion ? .opacity : .moveAndOpacity(edge: edge)
    }

    public static func transition(
        reduceMotion: Bool,
        edge: Edge = .top
    ) -> AnyTransition {
        switch transitionStyle(reduceMotion: reduceMotion, edge: edge) {
        case .opacity:
            .opacity
        case let .moveAndOpacity(edge):
            .move(edge: edge).combined(with: .opacity)
        }
    }

    private static func animation(for spec: SpringSpec) -> Animation {
        .spring(response: spec.response, dampingFraction: spec.dampingFraction)
    }
}

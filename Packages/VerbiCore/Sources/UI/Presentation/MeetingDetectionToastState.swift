import Foundation
import VerbiCoreDomain
import VerbiCoreInfrastructure

/// Represents the presentation state of the non-blocking meeting detection toast.
public enum MeetingDetectionToastState: Equatable, Sendable {
    case detected(app: CaptureOrigin, appName: String, context: ResolvedCaptureContext?)
    /// Retained for controller transition coverage and tests. Production no longer
    /// presents it: once a meeting recording starts the toast hides, and the
    /// recording pill plus menu bar stay the in-progress indicators.
    case recording(app: CaptureOrigin, appName: String, startedAt: Date)
    case endPrompt(app: CaptureOrigin, appName: String, startedAt: Date, deadline: Date)

    public var app: CaptureOrigin {
        switch self {
        case let .detected(app, _, _):
            app
        case let .recording(app, _, _):
            app
        case let .endPrompt(app, _, _, _):
            app
        }
    }

    public var appName: String {
        switch self {
        case let .detected(_, appName, _):
            appName
        case let .recording(_, appName, _):
            appName
        case let .endPrompt(_, appName, _, _):
            appName
        }
    }
}

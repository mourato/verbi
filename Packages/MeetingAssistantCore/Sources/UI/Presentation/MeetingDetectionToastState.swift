import Foundation
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

/// Represents the presentation state of the non-blocking meeting detection toast.
public enum MeetingDetectionToastState: Equatable, Sendable {
    case detected(app: MeetingApp, appName: String, context: ResolvedCaptureContext?)
    case recording(app: MeetingApp, appName: String, startedAt: Date)
    case ended(app: MeetingApp, appName: String, countdownSeconds: Int, totalCountdownSeconds: Int)

    public var app: MeetingApp {
        switch self {
        case let .detected(app, _, _):
            app
        case let .recording(app, _, _):
            app
        case let .ended(app, _, _, _):
            app
        }
    }

    public var appName: String {
        switch self {
        case let .detected(_, appName, _):
            appName
        case let .recording(_, appName, _):
            appName
        case let .ended(_, appName, _, _):
            appName
        }
    }
}

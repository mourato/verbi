import Foundation
import VerbiCoreDomain
import VerbiCoreInfrastructure

/// Represents the presentation state of the non-blocking meeting detection toast.
public enum MeetingDetectionToastState: Equatable, Sendable {
    case detected(app: CaptureOrigin, appName: String, context: ResolvedCaptureContext?)
    case recording(app: CaptureOrigin, appName: String, startedAt: Date)

    public var app: CaptureOrigin {
        switch self {
        case let .detected(app, _, _):
            app
        case let .recording(app, _, _):
            app
        }
    }

    public var appName: String {
        switch self {
        case let .detected(_, appName, _):
            appName
        case let .recording(_, appName, _):
            appName
        }
    }
}

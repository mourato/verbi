import Foundation

public enum AppDeepLink: String, CaseIterable, Sendable {
    case dictation
    case meeting
    case assistant
    case history
    case settings

    public static let scheme = AppIdentity.appURLScheme

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }

        let host = url.host?.lowercased() ?? ""
        if let match = Self(rawValue: host) {
            self = match
            return
        }

        let pathAction = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .first
            .map { String($0).lowercased() }
        guard let pathAction, let match = Self(rawValue: pathAction) else {
            return nil
        }
        self = match
    }
}

import Foundation

/// Inbound `verbi://` deep links for primary app actions.
public enum AppDeepLink: String, CaseIterable, Sendable {
    case dictation
    case meeting
    case assistant
    case history
    case settings

    public static let scheme = "verbi"

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }

        let host = url.host?.lowercased() ?? ""
        if let match = Self(rawValue: host) {
            self = match
            return
        }

        // Support path-style URLs such as `verbi:///dictation`.
        let pathAction = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .first
            .map { String($0).lowercased() }
        guard let pathAction, let match = Self(rawValue: pathAction) else {
            return nil
        }
        self = match
    }

    public var url: URL {
        // ponytail: force-unwrap is safe — scheme and rawValue are static ASCII tokens.
        URL(string: "\(Self.scheme)://\(rawValue)")!
    }
}

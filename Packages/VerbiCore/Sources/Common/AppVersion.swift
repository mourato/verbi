import Foundation

public enum AppVersion {
    private static let hardcodedVersion = "0.11.22"

    private static let hardcodedBuild = "170"

    public static var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? hardcodedVersion
    }

    public static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? hardcodedBuild
    }

    public static var full: String {
        "\(current) (\(build))"
    }

    public static var marketing: String {
        current
    }

    public static var components: (major: Int, minor: Int, patch: Int)? {
        let parts = current.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 3 else { return nil }
        return (major: parts[0], minor: parts[1], patch: parts[2])
    }
}

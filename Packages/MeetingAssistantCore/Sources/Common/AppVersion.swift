// AppVersion.swift
// MeetingAssistantCore
//
// Single source of truth for app version information.
// This file provides version constants that can be accessed from any target.

import Foundation

/// Centralized app version information accessible from all targets.
///
/// Uses a hybrid approach: reads from Bundle at runtime when available,
/// falls back to hardcoded constants for compile-time access or pre-bundle scenarios.
public enum AppVersion {

    // MARK: - Hardcoded Constants (Update these when releasing)

    /// Hardcoded version string - update this when releasing a new version
    private static let hardcodedVersion = "0.9.6"

    /// Hardcoded build number - update this when creating a new build
    private static let hardcodedBuild = "111"

    // MARK: - Public API

    /// Current app version (e.g., "0.1.1")
    ///
    /// Attempts to read from Bundle first, falls back to hardcoded constant.
    public static var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? hardcodedVersion
    }

    /// Current build number (e.g., "1")
    ///
    /// Attempts to read from Bundle first, falls back to hardcoded constant.
    public static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? hardcodedBuild
    }

    /// Full version string in format "0.1.1 (1)"
    public static var full: String {
        "\(current) (\(build))"
    }

    /// Marketing version string (alias for `current`)
    public static var marketing: String {
        current
    }

    /// Semantic version components
    public static var components: (major: Int, minor: Int, patch: Int)? {
        let parts = current.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 3 else { return nil }
        return (major: parts[0], minor: parts[1], patch: parts[2])
    }
}

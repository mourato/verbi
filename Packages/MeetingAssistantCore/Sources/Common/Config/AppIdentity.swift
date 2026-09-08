import Foundation

/// Centralized runtime identity values used across app and core modules.
public enum AppIdentity {
    public static let displayName = AppIdentityValues.displayName
    public static let bundleIdentifier = AppIdentityValues.bundleIdentifier
    public static let xpcServiceName = AppIdentityValues.xpcServiceName
    public static let logSubsystem = AppIdentityValues.logSubsystem
    public static let isRunningTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        NSClassFromString("XCTestCase") != nil

    // Keep these identifiers stable to preserve existing window toolbar/autosave state.
    public static let settingsToolbarIdentifier = AppIdentityValues.settingsToolbarIdentifier
    public static let settingsWindowAutosaveName = AppIdentityValues.settingsWindowAutosaveName
    public static let appSupportDirectoryName = AppIdentityValues.appSupportDirectoryName
    public static let logDirectoryName = AppIdentityValues.logDirectoryName
    public static let keychainServiceIdentifier = AppIdentityValues.keychainServiceIdentifier
    public static let hotkeySignatureSeed = AppIdentityValues.hotkeySignatureSeed
    public static let userDefaultsDomainMigrationFlag = AppIdentityValues.userDefaultsDomainMigrationFlag
    public static let legacyAppSupportDirectoryNames = AppIdentityValues.legacyAppSupportDirectoryNames
    public static let legacyLogDirectoryNames = AppIdentityValues.legacyLogDirectoryNames
    public static let legacyKeychainServiceIdentifiers = AppIdentityValues.legacyKeychainServiceIdentifiers
    public static let legacyUserDefaultsDomains = AppIdentityValues.legacyUserDefaultsDomains

    public static func appSupportBaseDirectory(fileManager: FileManager = .default) -> URL {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let currentURL = appSupportURL.appendingPathComponent(appSupportDirectoryName, isDirectory: true)
        let legacyURLs = legacyAppSupportDirectoryNames.map {
            appSupportURL.appendingPathComponent($0, isDirectory: true)
        }
        return resolveMigratedDirectory(currentURL: currentURL, legacyURLs: legacyURLs, fileManager: fileManager)
    }

    public static func logsBaseDirectory(fileManager: FileManager = .default) -> URL {
        let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let logsRootURL = libraryURL.appendingPathComponent("Logs", isDirectory: true)
        let currentURL = logsRootURL.appendingPathComponent(logDirectoryName, isDirectory: true)
        let legacyURLs = legacyLogDirectoryNames.map {
            logsRootURL.appendingPathComponent($0, isDirectory: true)
        }
        return resolveMigratedDirectory(currentURL: currentURL, legacyURLs: legacyURLs, fileManager: fileManager)
    }

    public static func cachesBaseDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
    }

    /// Moves the newest present legacy directory onto `currentURL` when current is absent.
    /// Legacy order is newest-first (e.g. Prisma before MeetingAssistant).
    public static func resolveMigratedDirectory(
        currentURL: URL,
        legacyURLs: [URL],
        fileManager: FileManager,
    ) -> URL {
        for legacyURL in legacyURLs {
            migrateLegacyDirectoryIfNeeded(from: legacyURL, to: currentURL, fileManager: fileManager)
            if fileManager.fileExists(atPath: currentURL.path) {
                return currentURL
            }
        }
        if fileManager.fileExists(atPath: currentURL.path) {
            return currentURL
        }
        for legacyURL in legacyURLs where fileManager.fileExists(atPath: legacyURL.path) {
            return legacyURL
        }
        return currentURL
    }

    private static func migrateLegacyDirectoryIfNeeded(from legacyURL: URL, to currentURL: URL, fileManager: FileManager) {
        guard fileManager.fileExists(atPath: legacyURL.path),
              !fileManager.fileExists(atPath: currentURL.path)
        else {
            return
        }

        do {
            try fileManager.moveItem(at: legacyURL, to: currentURL)
        } catch {
            // Keep fallback behavior in callers when migration fails.
        }
    }
}

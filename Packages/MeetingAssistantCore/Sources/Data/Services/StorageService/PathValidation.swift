import Foundation
import MeetingAssistantCoreCommon

extension FileSystemStorageService {

    // MARK: - Path Validation

    enum PathValidationError: Error, LocalizedError {
        case pathTraversalDetected(String)
        case invalidPath(String)
        case outsideContainer(String)

        var errorDescription: String? {
            switch self {
            case let .pathTraversalDetected(path):
                "Security: Path traversal attempt detected - \(path)"
            case let .invalidPath(path):
                "Security: Invalid path format - \(path)"
            case let .outsideContainer(path):
                "Security: Path outside app container - \(path)"
            }
        }
    }

    /// Validates that a path component is safe and within the app container.
    /// Use for relative paths or filenames only — NOT for full absolute paths.
    func validatePath(_ path: String) throws -> URL {
        do {
            try InputSanitizer.validatePathComponent(path)
        } catch {
            AppLogger.warning("Path traversal attempt blocked", category: .databaseManager, extra: ["path": path])
            throw PathValidationError.pathTraversalDetected(path)
        }

        let url = URL(fileURLWithPath: path)
        let resolvedPath = url.resolvingSymlinksInPath().path

        let containerPath = AppIdentity.appSupportBaseDirectory(fileManager: .default).path
        let appSupportRootURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let legacyContainerPaths = AppIdentity.legacyAppSupportDirectoryNames.map {
            appSupportRootURL.appendingPathComponent($0, isDirectory: true).path
        }
        let isInsideKnownContainer = resolvedPath.hasPrefix(containerPath)
            || legacyContainerPaths.contains { resolvedPath.hasPrefix($0) }
        guard isInsideKnownContainer else {
            AppLogger.warning("Path outside container blocked", category: .databaseManager, extra: [
                "path": path,
                "resolved": resolvedPath,
                "container": containerPath,
            ])
            throw PathValidationError.outsideContainer(path)
        }

        return URL(fileURLWithPath: resolvedPath)
    }

    /// Validates a full absolute path for use as a recording directory.
    ///
    /// Unlike `validatePath(_:)`, this method is designed for user-configured
    /// **absolute paths** (e.g. `/Users/usuario/Documents/recordings`).
    /// It guards against path traversal (`..`) but intentionally allows paths
    /// outside the app container, since the user explicitly chose them.
    func validateRecordingPath(_ path: String) throws -> URL {
        guard !path.isEmpty else {
            throw PathValidationError.invalidPath(path)
        }

        // Check the ORIGINAL path for traversal sequences BEFORE resolution.
        // After resolution, ".." is collapsed and invisible.
        let originalComponents = (path as NSString).pathComponents
        if originalComponents.contains("..") {
            AppLogger.warning(
                "Path traversal attempt blocked in recording path",
                category: .databaseManager,
                extra: ["path": path],
            )
            throw PathValidationError.pathTraversalDetected(path)
        }

        let url = URL(fileURLWithPath: path)
        let resolvedPath = url.resolvingSymlinksInPath().path

        // Ensure the resolved path is under the user's home directory or /Volumes.
        // Recording directories should be user-accessible locations, not system paths.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let isUserAccessible = resolvedPath.hasPrefix(home) || resolvedPath.hasPrefix("/Volumes/")
        guard isUserAccessible else {
            AppLogger.warning(
                "Recording path outside user-accessible location blocked",
                category: .databaseManager,
                extra: ["path": path, "resolved": resolvedPath, "home": home],
            )
            throw PathValidationError.outsideContainer(path)
        }

        return URL(fileURLWithPath: resolvedPath)
    }
}

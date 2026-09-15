import Foundation
import MeetingAssistantCoreCommon

enum MeetingNotesEditorThemeResolver {
    static let themesDirectoryName = "MeetingNotes/Themes"

    static func themesDirectory(
        appSupportRoot: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL {
        let root = appSupportRoot ?? AppIdentity.appSupportBaseDirectory(fileManager: fileManager)
        return root.appendingPathComponent(themesDirectoryName, isDirectory: true)
    }

    static func ensureThemesDirectoryExists(
        appSupportRoot: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let directory = themesDirectory(appSupportRoot: appSupportRoot, fileManager: fileManager)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func availableThemeNames(
        appSupportRoot: URL? = nil,
        fileManager: FileManager = .default
    ) -> [String] {
        let directory = themesDirectory(appSupportRoot: appSupportRoot, fileManager: fileManager)
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .filter { $0.pathExtension.lowercased() == "css" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    static func css(
        forThemeName name: String,
        appSupportRoot: URL? = nil,
        fileManager: FileManager = .default
    ) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let fileURL = themesDirectory(appSupportRoot: appSupportRoot, fileManager: fileManager)
            .appendingPathComponent("\(trimmed).css")
        guard fileManager.fileExists(atPath: fileURL.path) else { return "" }
        return (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }
}

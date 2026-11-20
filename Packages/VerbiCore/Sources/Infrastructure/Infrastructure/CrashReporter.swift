import Foundation
import os.log
import VerbiCoreCommon

public final class CrashReporter: Sendable {
    public static let shared = CrashReporter()

    private let logDirectory: URL

    private init() {
        let fileManager = FileManager.default
        let logsURL = AppIdentity.logsBaseDirectory(fileManager: fileManager)
            .appendingPathComponent("CrashReports", isDirectory: true)
        logDirectory = logsURL

        try? fileManager.createDirectory(at: logsURL, withIntermediateDirectories: true, attributes: nil)
    }

    public func setup() {
        NSSetUncaughtExceptionHandler { exception in
            CrashReporter.shared.handleException(exception)
        }

        AppLogger.info("CrashReporter installed. Logs at: \(logDirectory.path)", category: .health)
    }

    private func handleException(_ exception: NSException) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let filename = "crash-\(timestamp).log"
        let fileURL = logDirectory.appendingPathComponent(filename)

        let report = """
        CRASH REPORT - \(timestamp)
        ======================================================================
        Name: \(exception.name.rawValue)
        Reason: \(exception.reason ?? "Unknown")

        Stack Trace:
        \(exception.callStackSymbols.joined(separator: "\n"))

        User Info:
        \(exception.userInfo?.description ?? "None")
        ======================================================================
        """

        do {
            try report.write(to: fileURL, atomically: true, encoding: .utf8)
            AppLogger.fault("App Crashed! Saved report to \(fileURL.lastPathComponent)", category: .health)
        } catch {
            print("Failed to write crash report: \(error)")
        }
    }

    public func cleanup() {
        AppLogger.debug("CrashReporter cleanup completed", category: .health)
    }
}

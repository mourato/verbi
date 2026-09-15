import Foundation
import os.log

/// Centralized logger for the application using os.log
// swiftlint:disable:next orphaned_doc_comment
// swiftlint:disable discouraged_optional_collection
public enum AppLogger {
    private static let subsystem = AppIdentity.logSubsystem

    // MARK: - Public API

    public static func debug(_ message: String, category: LogCategory, extra: [String: Any] = [:]) {
        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        let formattedMessage = format(message, extra: extra)
        #if DEBUG
            logger.debug("\(formattedMessage, privacy: .public)")
        #else
            logger.debug("\(formattedMessage, privacy: .private)")
        #endif
    }

    public static func info(_ message: String, category: LogCategory, extra: [String: Any] = [:]) {
        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        let formattedMessage = format(message, extra: extra)
        #if DEBUG
            logger.info("\(formattedMessage, privacy: .public)")
        #else
            logger.info("\(formattedMessage, privacy: .private)")
        #endif
    }

    public static func warning(_ message: String, category: LogCategory, extra: [String: Any] = [:]) {
        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        let formattedMessage = format(message, extra: extra)
        #if DEBUG
            logger.warning("\(formattedMessage, privacy: .public)")
        #else
            logger.warning("\(formattedMessage, privacy: .private)")
        #endif
    }

    /// Log an error (recoverable issues)
    public static func error(_ message: String, category: LogCategory, error: Error? = nil, extra: [String: Any] = [:]) {
        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        var detailedMessage = message

        if let error {
            detailedMessage += " | Error: \(error.localizedDescription)"
        }

        let formattedMessage = format(detailedMessage, extra: extra)
        logger.error("\(formattedMessage, privacy: .public)")
    }

    /// Log a fault (critical issues/crashes)
    public static func fault(_ message: String, category: LogCategory, error: Error? = nil, extra: [String: Any] = [:]) {
        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        var detailedMessage = message

        if let error {
            detailedMessage += " | Error: \(error.localizedDescription)"
        }

        let formattedMessage = format(detailedMessage, extra: extra)
        logger.fault("\(formattedMessage, privacy: .public)")
    }

    // MARK: - Private Helpers

    private static func format(_ message: String, extra: [String: Any]?) -> String {
        guard let extra, !extra.isEmpty else {
            return message
        }

        let extraString = extra.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        return "\(message) [\(extraString)]"
    }
}

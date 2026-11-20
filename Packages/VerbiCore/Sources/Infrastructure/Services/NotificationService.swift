import Foundation
import os.log
import UserNotifications
import VerbiCoreCommon

@MainActor
public final class NotificationService {
    public static let shared = NotificationService()

    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "NotificationService")

    private init() {}

    public func requestAuthorization() {
        guard isRunningAsAppBundle else {
            logger.info("Running as CLI tool, skipping UNUserNotificationCenter authorization")
            return
        }

        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { [weak self] granted, error in
            if let error {
                self?.logger.error(
                    "Notification authorization failed: \(error.localizedDescription)"
                )
            } else if !granted {
                self?.logger.warning("Notification authorization denied by user")
            }
        }
    }

    public func sendNotification(title: String, body: String) {
        if isRunningAsAppBundle {
            sendNotificationViaUserNotifications(title: title, body: body)
        } else {
            #if DEBUG
                sendNotificationViaAppleScript(title: title, body: body)
            #endif
        }
    }

    private var isRunningAsAppBundle: Bool {
        guard let bundleId = Bundle.main.bundleIdentifier else { return false }
        return !bundleId.lowercased().contains("xctest")
    }

    private func sendNotificationViaUserNotifications(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error {
                self?.logger.error("Failed to deliver notification: \(error.localizedDescription)")
            }
        }
    }

    #if DEBUG
        private func sendNotificationViaAppleScript(title: String, body: String) {
            let sanitizedTitle = sanitizeForAppleScript(title)
            let sanitizedBody = sanitizeForAppleScript(body)

            let script =
                "display notification \"\(sanitizedBody)\" with title \"\(sanitizedTitle)\" sound name \"default\""

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]

            do {
                try process.run()
            } catch {
                logger.error("Failed to send notification via osascript: \(error.localizedDescription)")
            }
        }
    #endif

    private func sanitizeForAppleScript(_ input: String) -> String {
        var result = input.replacingOccurrences(of: "\\", with: "\\\\")
        result = result.replacingOccurrences(of: "\"", with: "\\\"")

        let dangerousPatterns: [(pattern: String, replacement: String)] = [
            ("`", "'"),
            ("$", ""),
            ("\n", " "),
            ("\r", " "),
            ("\t", " "),
            ("«", ""),
            ("»", "")
        ]

        for (pattern, replacement) in dangerousPatterns {
            result = result.replacingOccurrences(of: pattern, with: replacement)
        }

        let maxLength = 200
        if result.count > maxLength {
            result = String(result.prefix(maxLength)) + "..."
        }

        return result
    }
}

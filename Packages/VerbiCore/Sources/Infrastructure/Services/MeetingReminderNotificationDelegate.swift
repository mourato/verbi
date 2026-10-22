import AppKit
import Foundation
import UserNotifications

enum MeetingReminderNotificationConstants {
    static let joinActionIdentifier = "meetingReminder.join"
}

final class MeetingReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == MeetingReminderNotificationConstants.joinActionIdentifier else { return }
        guard let urlString = response.notification.request.content.userInfo["joinURL"] as? String,
              let url = URL(string: urlString)
        else { return }

        await MainActor.run {
            _ = NSWorkspace.shared.open(url)
        }
    }
}

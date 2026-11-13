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
        if response.actionIdentifier == MeetingReminderNotificationConstants.joinActionIdentifier, let urlString = response.notification.request.content.userInfo["joinURL"] as? String,
           let url = URL(string: urlString)
        {
            await MainActor.run {
                _ = NSWorkspace.shared.open(url)
            }
            return
        }

        guard response.notification.request.content.categoryIdentifier == InterruptedRecoveryNotificationConstants.categoryIdentifier else {
            return
        }
        guard response.actionIdentifier == InterruptedRecoveryNotificationConstants.showActionIdentifier
            || response.actionIdentifier == UNNotificationDefaultActionIdentifier
        else {
            return
        }

        await MainActor.run {
            NavigationService.shared.openHistory()
        }
    }
}

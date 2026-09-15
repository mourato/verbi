import AppKit
import Foundation
import MeetingAssistantCoreCommon
import os.log
import UserNotifications

public extension NotificationService {
    static let meetingReminderLeadCategoryIdentifier = "meetingReminder.lead"
    static let meetingReminderJoinActionIdentifier = MeetingReminderNotificationConstants.joinActionIdentifier

    static func meetingLeadNotificationIdentifier(for occurrenceKey: String) -> String {
        "meeting-reminder-lead-\(occurrenceKey)"
    }

    static var isAppBundleContext: Bool {
        guard let bundleId = Bundle.main.bundleIdentifier else { return false }
        return !bundleId.lowercased().contains("xctest")
    }

    func registerMeetingReminderCategories() {
        guard Self.isAppBundleContext else { return }

        let joinAction = UNNotificationAction(
            identifier: Self.meetingReminderJoinActionIdentifier,
            title: "meeting_reminder.notification.join".localized,
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.meetingReminderLeadCategoryIdentifier,
            actions: [joinAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
        UNUserNotificationCenter.current().delegate = Self.meetingReminderDelegate
    }

    private static let meetingReminderDelegate = MeetingReminderNotificationDelegate()

    func scheduleMeetingLeadNotification(
        occurrenceKey: String,
        at fireDate: Date,
        title: String,
        body: String,
        joinURL: URL?
    ) {
        guard Self.isAppBundleContext else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.meetingReminderLeadCategoryIdentifier
        if let joinURL {
            content.userInfo = ["joinURL": joinURL.absoluteString]
        }

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.meetingLeadNotificationIdentifier(for: occurrenceKey),
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLogger.error(
                    "Failed to schedule meeting lead notification",
                    category: .recordingManager,
                    error: error
                )
            }
        }
    }

    func cancelMeetingLeadNotification(occurrenceKey: String) {
        guard Self.isAppBundleContext else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.meetingLeadNotificationIdentifier(for: occurrenceKey)]
        )
    }
}

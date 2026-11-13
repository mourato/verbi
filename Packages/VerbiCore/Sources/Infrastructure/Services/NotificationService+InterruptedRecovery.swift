import Foundation
import UserNotifications
import VerbiCoreCommon
import VerbiCoreDomain

enum InterruptedRecoveryNotificationConstants {
    static let categoryIdentifier = "recovery.interrupted"
    static let showActionIdentifier = "recovery.interrupted.showLibrary"
}

public extension NotificationService {
    /// Posts one summary notification after an interrupted-recording recovery
    /// scan. Tapping the notification or its action opens the library.
    /// No-op in test/CLI contexts, matching the base notification service.
    func sendInterruptedRecoveryNotification(recoveredCount: Int) {
        guard Self.isAppBundleContext, recoveredCount > 0 else { return }

        registerInterruptedRecoveryCategory()

        let content = UNMutableNotificationContent()
        content.title = InterruptedRecordingRecovery.notificationTitle()
        content.body = InterruptedRecordingRecovery.notificationBody(recoveredCount: recoveredCount)
        content.sound = .default
        content.categoryIdentifier = InterruptedRecoveryNotificationConstants.categoryIdentifier

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLogger.error("Failed to deliver recovery notification", category: .recordingManager, error: error)
            }
        }
    }

    /// Registers the recovery category alongside any already-registered
    /// categories (for example meeting reminders) instead of replacing them.
    func registerInterruptedRecoveryCategory() {
        guard Self.isAppBundleContext else { return }

        // Reuse the meeting-reminder registration so the shared delegate and
        // the lead category stay in place.
        registerMeetingReminderCategories()

        let showLibraryAction = UNNotificationAction(
            identifier: InterruptedRecoveryNotificationConstants.showActionIdentifier,
            title: "recovery.interrupted.notification.action".localized,
            options: [.foreground]
        )
        let recoveryCategory = UNNotificationCategory(
            identifier: InterruptedRecoveryNotificationConstants.categoryIdentifier,
            actions: [showLibraryAction],
            intentIdentifiers: [],
            options: []
        )

        let center = UNUserNotificationCenter.current()
        center.getNotificationCategories { existing in
            var updated = existing.filter { $0.identifier != InterruptedRecoveryNotificationConstants.categoryIdentifier }
            updated.insert(recoveryCategory)
            center.setNotificationCategories(updated)
        }
    }
}

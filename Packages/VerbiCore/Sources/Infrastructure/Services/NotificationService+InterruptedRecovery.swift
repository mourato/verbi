import Foundation
import UserNotifications
import VerbiCoreCommon
import VerbiCoreDomain

enum InterruptedRecoveryNotificationConstants {
    static let categoryIdentifier = "recovery.interrupted"
    static let showActionIdentifier = "recovery.interrupted.showLibrary"
}

public extension NotificationService {
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

    func registerInterruptedRecoveryCategory() {
        guard Self.isAppBundleContext else { return }

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

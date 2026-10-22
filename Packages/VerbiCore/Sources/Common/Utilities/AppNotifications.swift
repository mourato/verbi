import Foundation

public enum AppNotifications {
    public enum UserInfoKey {
        public static let transcriptionId = "transcriptionId"
        public static let transcriptionErrorMessage = "transcriptionErrorMessage"
        public static let shortcutCaptureHealthStatus = "shortcutCaptureHealthStatus"
    }
}

public extension Notification.Name {
    static let meetingAssistantTranscriptionSaved = Notification.Name("meetingAssistant.transcription.saved")
    static let meetingAssistantTranscriptionFailed = Notification.Name("meetingAssistant.transcription.failed")
    static let meetingAssistantShortcutCaptureHealthDidChange = Notification.Name("meetingAssistant.shortcutCaptureHealth.didChange")
}

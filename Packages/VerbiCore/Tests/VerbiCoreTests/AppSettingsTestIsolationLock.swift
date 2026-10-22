import Darwin
import Foundation

@MainActor
enum AppSettingsTestIsolationLock {
    private static let lockFilePath = NSTemporaryDirectory() + "meetingassistant-appsettings-tests.lock"
    private static var lockFileDescriptor: Int32 = -1

    static func acquire() throws {
        if lockFileDescriptor == -1 {
            let descriptor = open(lockFilePath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else {
                throw lockError("Failed to open AppSettings test lock file")
            }
            lockFileDescriptor = descriptor
        }

        guard flock(lockFileDescriptor, LOCK_EX) == 0 else {
            throw lockError("Failed to acquire AppSettings test lock")
        }
    }

    static func release() {
        guard lockFileDescriptor >= 0 else { return }
        _ = flock(lockFileDescriptor, LOCK_UN)
    }

    private static func lockError(_ message: String) -> NSError {
        let errorMessage = String(cString: strerror(errno))
        return NSError(
            domain: "AppSettingsTestIsolationLock",
            code: Int(errno),
            userInfo: [NSLocalizedDescriptionKey: "\(message): \(errorMessage)"],
        )
    }
}

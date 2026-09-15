import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain

/// Actor isolating recording state for Swift 6 concurrency.
/// Owns mutable shared state and prevents race conditions.
public actor RecordingActor {
    // MARK: - Isolated State

    private var isRecording = false
    private var isTranscribing = false
    private var currentMeeting: Meeting?
    private var lastError: Error?
    private var hasRequiredPermissions = false
    private var micAudioURL: URL?
    private var systemAudioURL: URL?
    private var mergedAudioURL: URL?

    public init() {}

    // MARK: - Thread-Safe State Access

    public var recordingState: Bool {
        isRecording
    }

    public var transcribingState: Bool {
        isTranscribing
    }

    public var currentMeetingState: Meeting? {
        currentMeeting
    }

    public var lastErrorState: Error? {
        lastError
    }

    public var permissionsState: Bool {
        hasRequiredPermissions
    }

    public var micAudioURLState: URL? {
        micAudioURL
    }

    public var systemAudioURLState: URL? {
        systemAudioURL
    }

    public var mergedAudioURLState: URL? {
        mergedAudioURL
    }

    // MARK: - Mutation

    public func setRecording(_ value: Bool) {
        isRecording = value
        AppLogger.debug("Recording state updated to: \(value)", category: .recordingManager)
    }

    public func setTranscribing(_ value: Bool) {
        isTranscribing = value
        AppLogger.debug("Transcribing state updated to: \(value)", category: .recordingManager)
    }

    public func setCurrentMeeting(_ meeting: Meeting?) {
        currentMeeting = meeting
        AppLogger.debug("Current meeting updated: \(meeting?.app.displayName ?? "nil")", category: .recordingManager)
    }

    public func setLastError(_ error: Error?) {
        lastError = error
        if let error {
            AppLogger.error("Last error updated", category: .recordingManager, error: error)
        }
    }

    public func setPermissions(_ hasPermissions: Bool) {
        hasRequiredPermissions = hasPermissions
        AppLogger.debug("Permissions state updated to: \(hasPermissions)", category: .recordingManager)
    }

    public func setMicAudioURL(_ url: URL?) {
        micAudioURL = url
    }

    public func setSystemAudioURL(_ url: URL?) {
        systemAudioURL = url
    }

    public func setMergedAudioURL(_ url: URL?) {
        mergedAudioURL = url
    }

    public func clearTemporaryURLs() {
        micAudioURL = nil
        systemAudioURL = nil
        mergedAudioURL = nil
    }

    // MARK: - Utilities

    public func createMeeting(app: MeetingApp) -> Meeting {
        let meeting = Meeting(app: app)
        currentMeeting = meeting
        return meeting
    }

    public func updateMeetingEndTime() {
        currentMeeting?.endTime = Date()
    }

    public func updateMeetingAudioPath(_ path: String) {
        currentMeeting?.audioFilePath = path
    }

    public func reset() {
        isRecording = false
        isTranscribing = false
        currentMeeting = nil
        lastError = nil
        micAudioURL = nil
        systemAudioURL = nil
        mergedAudioURL = nil
    }
}

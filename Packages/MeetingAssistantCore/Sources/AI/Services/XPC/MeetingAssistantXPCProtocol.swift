import Foundation
import MeetingAssistantCoreCommon

/// Protocol for the MeetingAssistant XPC Service.
/// This service handles heavy AI processing (Diarization, Transcription).
@objc(MeetingAssistantXPCProtocol)
public protocol MeetingAssistantXPCProtocol {
    /// Transcribes an audio file with optional diarization.
    /// - Parameters:
    ///   - audioURL: The URL of the audio file to process.
    ///   - settingsData: JSON encoded `MeetingAssistantXPCModels.AppSettings`.
    ///   - reply: Callback with JSON encoded `TranscriptionResponse` or error.
    func transcribe(
        audioURL: URL,
        settingsData: Data,
        withReply reply: @escaping @Sendable (Data?, Error?) -> Void
    )

    /// Fetches the current status of the AI service.
    /// - Parameter reply: Callback with JSON encoded `MeetingAssistantXPCModels.ServiceStatus` or error.
    func fetchServiceStatus(withReply reply: @escaping @Sendable (Data?, Error?) -> Void)

    /// Warms up the models inside the XPC process.
    /// - Parameter reply: Callback indicating success or error.
    func warmupModel(withReply reply: @escaping @Sendable (Error?) -> Void)
}

/// Constants for XPC Service
public enum MeetingAssistantXPCConstants {
    public static let serviceName = AppIdentity.xpcServiceName
}

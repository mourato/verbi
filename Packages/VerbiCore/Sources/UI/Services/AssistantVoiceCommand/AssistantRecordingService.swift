import Foundation
import VerbiCoreAudio
import VerbiCoreDomain

@MainActor
public protocol AssistantRecordingService: AnyObject {
    var isRecording: Bool { get }
    func startRecording(to outputURL: URL, source: RecordingSource, retryCount: Int) async throws
    func stopRecording() async -> URL?
    func hasPermission() async -> Bool
    func requestPermission() async
}

extension AudioRecorder: AssistantRecordingService {}

public extension AssistantRecordingService {
    func startRecording(to outputURL: URL, source: RecordingSource) async throws {
        try await startRecording(to: outputURL, source: source, retryCount: 0)
    }
}

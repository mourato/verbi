import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

@MainActor
public protocol MeetingQuestionDictationRecording: AnyObject {
    func startQuestionDictationRecording(to outputURL: URL) async throws
    func stopQuestionDictationRecording() async -> URL?
    func hasPermission() async -> Bool
    func requestPermission() async
}

@MainActor
public protocol MeetingQuestionDictationTranscribing: AnyObject {
    func transcribeQuestionDictation(audioURL: URL) async throws -> TranscriptionResponse
}

extension AudioRecorder: MeetingQuestionDictationRecording {
    public func startQuestionDictationRecording(to outputURL: URL) async throws {
        try await startRecording(to: outputURL, source: .microphone)
    }

    public func stopQuestionDictationRecording() async -> URL? {
        await stopRecording()
    }
}

extension TranscriptionClient: MeetingQuestionDictationTranscribing {
    public func transcribeQuestionDictation(audioURL: URL) async throws -> TranscriptionResponse {
        try await transcribe(
            audioURL: audioURL,
            onProgress: nil,
            executionMode: .dictation
        )
    }
}

@MainActor
public final class MeetingQuestionDictationService: ObservableObject {
    public enum State: Equatable {
        case idle
        case recording
        case processing
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var errorMessage: String?

    private let recorder: any MeetingQuestionDictationRecording
    private let transcriber: any MeetingQuestionDictationTranscribing
    private var recordingURL: URL?

    public init(
        recorder: any MeetingQuestionDictationRecording = AudioRecorder.shared,
        transcriber: any MeetingQuestionDictationTranscribing = TranscriptionClient.shared
    ) {
        self.recorder = recorder
        self.transcriber = transcriber
    }

    public var isBusy: Bool {
        state == .recording || state == .processing
    }

    public func clearError() {
        errorMessage = nil
    }

    public func toggleDictation() async -> String? {
        switch state {
        case .idle:
            await startDictation()
            return nil
        case .recording:
            return await finishDictation()
        case .processing:
            return nil
        }
    }

    public func cancel() async {
        guard state != .idle else { return }

        _ = await recorder.stopQuestionDictationRecording()
        await RecordingExclusivityCoordinator.shared.endAssistant()
        cleanupRecordingFile(recordingURL)
        recordingURL = nil
        state = .idle
    }

    private func startDictation() async {
        errorMessage = nil

        guard await RecordingExclusivityCoordinator.shared.beginAssistant() else {
            errorMessage = "transcription.qa.dictation.error.busy".localized
            return
        }

        let hasPermission = await recorder.hasPermission()
        if !hasPermission {
            await recorder.requestPermission()
        }

        guard await recorder.hasPermission() else {
            await RecordingExclusivityCoordinator.shared.endAssistant()
            errorMessage = "transcription.qa.dictation.error.microphone_permission".localized
            return
        }

        let outputURL = makeTemporaryRecordingURL()
        recordingURL = outputURL

        do {
            try await recorder.startQuestionDictationRecording(to: outputURL)
            state = .recording
        } catch {
            await RecordingExclusivityCoordinator.shared.endAssistant()
            cleanupRecordingFile(outputURL)
            recordingURL = nil
            state = .idle
            errorMessage = "transcription.qa.dictation.error.start_failed".localized
        }
    }

    private func finishDictation() async -> String? {
        state = .processing

        let recordedURL = await recorder.stopQuestionDictationRecording() ?? recordingURL
        await RecordingExclusivityCoordinator.shared.endAssistant()

        defer {
            cleanupRecordingFile(recordedURL)
            recordingURL = nil
            state = .idle
        }

        guard let recordedURL else {
            errorMessage = "transcription.qa.dictation.error.stop_failed".localized
            return nil
        }

        do {
            let response = try await transcriber.transcribeQuestionDictation(audioURL: recordedURL)
            let transcribedText = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcribedText.isEmpty else {
                errorMessage = "transcription.qa.dictation.error.empty_result".localized
                return nil
            }

            errorMessage = nil
            return transcribedText
        } catch {
            errorMessage = "transcription.qa.dictation.error.transcription".localized
            return nil
        }
    }

    private func makeTemporaryRecordingURL() -> URL {
        let fileName = "meeting-question-dictation-\(UUID().uuidString).m4a"
        return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }

    private func cleanupRecordingFile(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

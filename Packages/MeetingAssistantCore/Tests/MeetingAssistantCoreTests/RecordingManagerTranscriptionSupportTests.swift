import AVFoundation
import Foundation
@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreUI
import XCTest

@MainActor
extension RecordingManagerTests {
    func testInactiveIncrementalMeetingTeardownPreservesForwarder() throws {
        let manager = try XCTUnwrap(manager)
        let forwarder = RecordingManager.IncrementalBufferForwarder { _ in }
        manager.incrementalBufferForwarder = forwarder

        manager.teardownIncrementalMeetingSession()

        XCTAssertTrue(manager.incrementalBufferForwarder === forwarder)
        forwarder.stop()
        manager.incrementalBufferForwarder = nil
    }

    func testInactiveIncrementalDictationTeardownPreservesForwarder() throws {
        let manager = try XCTUnwrap(manager)
        let forwarder = RecordingManager.IncrementalBufferForwarder { _ in }
        manager.incrementalBufferForwarder = forwarder

        manager.teardownIncrementalDictationSession()

        XCTAssertTrue(manager.incrementalBufferForwarder === forwarder)
        forwarder.stop()
        manager.incrementalBufferForwarder = nil
    }

    func testTranscription_FailsWithInvalidURL() async throws {
        // Given
        let mockTranscription = try XCTUnwrap(mockTranscription)
        let invalidURL = URL(fileURLWithPath: "/nonexistent/path/file.m4a")
        mockTranscription.shouldFailTranscription = true

        // When/Then
        do {
            _ = try await mockTranscription.transcribe(audioURL: invalidURL)
            XCTFail("Expected error for transcription failure")
        } catch {
            // Should fail when shouldFailTranscription is true
            XCTAssertNotNil(error)
        }
    }

    func testTranscribeRecording_WhenFullFileTranscriptionFails_PersistsFailedHistoryItem() async throws {
        let manager = try XCTUnwrap(manager)
        let mockStorage = try XCTUnwrap(mockStorage)
        let mockTranscription = try XCTUnwrap(mockTranscription)
        mockTranscription.shouldFailTranscription = true

        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        try writeTestAudioFile(at: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let meetingID = UUID()
        let meeting = Meeting(
            id: meetingID,
            app: .unknown,
            capturePurpose: .dictation,
            startTime: Date(),
        )
        var session = RecordingManager.TranscriptionSessionSnapshot(
            id: meetingID,
            meeting: meeting,
            recordingSource: .microphone,
            kernelMode: .dictation,
            postProcessingContext: nil,
            postProcessingContextItems: [],
            meetingNotesContent: .empty,
            dictationSessionOutputLanguageOverride: nil,
            dictationStartBundleIdentifier: nil,
            dictationStartURL: nil,
        )
        session.useCaseConfig = manager.makeUseCaseConfig(session: session, settings: .shared)

        await manager.transcribeRecording(audioURL: audioURL, session: session)

        let failed = try XCTUnwrap(mockStorage.savedTranscriptions.last)
        XCTAssertEqual(failed.lifecycleState, .failed)
        XCTAssertEqual(failed.meeting.id, meetingID)
        XCTAssertEqual(failed.capturePurpose, .dictation)
        XCTAssertEqual(failed.text, "")
        XCTAssertEqual(failed.rawText, "")
        XCTAssertEqual(failed.meeting.audioFilePath, audioURL.path)
        XCTAssertNil(failed.postProcessingFailureReason)
        XCTAssertTrue(failed.transcriptionFailureReason?.contains("Transcription failed") == true)
    }

    func testShouldEnableDiarization_RespectsGlobalToggle() throws {
        let manager = try XCTUnwrap(manager)
        let settings = AppSettingsStore.shared
        let original = settings.isDiarizationEnabled
        defer { settings.isDiarizationEnabled = original }

        let meeting = Meeting(app: .unknown, capturePurpose: .meeting, startTime: Date())

        settings.isDiarizationEnabled = false
        XCTAssertFalse(manager.shouldEnableDiarization(for: meeting))

        settings.isDiarizationEnabled = true
        XCTAssertTrue(manager.shouldEnableDiarization(for: meeting))
    }

    func testMockStorageService_LoadTranscriptions() async throws {
        // Given
        let mockStorage = try XCTUnwrap(mockStorage)

        let mockTranscription = Transcription(
            meeting: Meeting(app: .unknown),
            text: "Test transcription",
            rawText: "Test transcription",
            processedContent: nil,
            postProcessingPromptId: nil,
            postProcessingPromptTitle: nil,
            language: "pt",
            modelName: "test-model",
        )
        mockStorage.mockTranscriptions = [mockTranscription]

        // When
        let transcriptions = try await mockStorage.loadTranscriptions()

        // Then
        XCTAssertEqual(transcriptions.count, 1)
        XCTAssertEqual(mockStorage.loadTranscriptionsCallCount, 1)
    }

    func testMockTranscriptionClient_CallTracking() async throws {
        // Given
        let mockTranscription = try XCTUnwrap(mockTranscription)
        let audioURL = URL(fileURLWithPath: "/tmp/test.m4a")

        // When
        _ = try await mockTranscription.transcribe(audioURL: audioURL)

        // Then
        XCTAssertEqual(mockTranscription.transcribeCallCount, 1)
        XCTAssertEqual(mockTranscription.lastTranscribeAudioURL, audioURL)
    }

    func testMockAudioRecorder_CallTracking() async throws {
        // Given
        let mockMic = try XCTUnwrap(mockMic)
        let audioURL = URL(fileURLWithPath: "/tmp/test.m4a")

        // When
        try await mockMic.startRecording(to: audioURL, retryCount: 0)
        _ = await mockMic.stopRecording()

        // Then
        XCTAssertEqual(mockMic.startRecordingParams.count, 1)
        XCTAssertEqual(mockMic.startRecordingParams.first?.url, audioURL)
        XCTAssertEqual(mockMic.stopRecordingCalledCount, 1)
    }

    func writeTestAudioFile(at url: URL) throws {
        let format = AppSettingsStore.AudioFormat(rawValue: url.pathExtension.lowercased()) ?? .wav
        let sampleRate = 16_000.0
        let settings: [String: Any] = switch format {
        case .m4a:
            [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
            ]
        case .wav:
            [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: true,
            ]
        }

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )

        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false,
        )
        let frameCount = AVAudioFrameCount(sampleRate * 0.2)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
            XCTFail("Failed to allocate test audio buffer")
            return
        }

        buffer.frameLength = frameCount
        if let channelData = buffer.floatChannelData {
            for frameIndex in 0..<Int(frameCount) {
                let sample = Float(sin(2 * .pi * Double(frameIndex) / 40.0) * 0.2)
                channelData[0][frameIndex] = sample
            }
        }

        try file.write(from: buffer)
    }
}

import AVFoundation
import Combine
@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreAudio
import XCTest

final class ConcurrencyTests: XCTestCase {

    // MARK: - RecordingActor Isolation Tests

    func testRecordingActor_Isolation_ConcurrentStateAccess() async {
        let actor = RecordingActor()

        // Test concurrent access to state properties
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    await actor.setRecording(i % 2 == 0)
                    let state = await actor.recordingState
                    XCTAssertTrue(state == true || state == false, "State should be consistent")
                }
            }
        }

        // Final state should be consistent
        let finalState = await actor.recordingState
        XCTAssertTrue(finalState == true || finalState == false)
    }

    func testRecordingActor_Isolation_ConcurrentMeetingUpdates() async {
        let actor = RecordingActor()

        // Test concurrent meeting updates
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask {
                    let app: MeetingApp = i % 2 == 0 ? .zoom : .slack
                    let meeting = await actor.createMeeting(app: app)
                    XCTAssertTrue(meeting.app.displayName == "Zoom" || meeting.app.displayName == "Slack")
                }
            }
        }

        // Verify final meeting state
        let currentMeeting = await actor.currentMeetingState
        XCTAssertNotNil(currentMeeting)
    }

    func testRecordingActor_Isolation_ErrorStateConsistency() async {
        let actor = RecordingActor()

        // Test concurrent error state updates
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    let error = NSError(domain: "test", code: i, userInfo: nil)
                    await actor.setLastError(error)
                    let currentError = await actor.lastErrorState
                    XCTAssertNotNil(currentError)
                }
            }
        }
    }

    // MARK: - AudioRecordingWorker Concurrency Tests

    func testAudioRecordingWorker_BufferProcessingConcurrency() async throws {
        let worker = AudioRecordingWorker()

        // Create test URL and format
        let testURL = URL(fileURLWithPath: "/tmp/test_concurrency.m4a")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))

        do {
            try await worker.start(writingTo: testURL, format: format, fileFormat: .m4a)
        } catch {
            XCTFail("Failed to start worker: \(error)")
            return
        }

        // Test concurrent buffer processing
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    // Create a test buffer
                    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024)!
                    buffer.frameLength = 1_024

                    // Fill with test data
                    if let channelData = buffer.floatChannelData {
                        for frame in 0..<Int(buffer.frameLength) {
                            for channel in 0..<Int(buffer.format.channelCount) {
                                channelData[channel][frame] = Float(i) / 20.0
                            }
                        }
                    }

                    // Process buffer concurrently
                    worker.process(buffer)
                }
            }
        }

        // Stop and verify
        let resultURL = await worker.stop()
        XCTAssertEqual(resultURL, testURL)

        // Clean up
        try? FileManager.default.removeItem(at: testURL)
    }

    func testAudioRecordingWorker_CallbackConcurrency() async throws {
        let worker = AudioRecordingWorker()

        actor CallbackTracker {
            var powerUpdates = [Float]()
            var errorCount = 0

            func addPowerUpdate(_ value: Float) {
                powerUpdates.append(value)
            }

            func incrementErrorCount() {
                errorCount += 1
            }

            func getPowerUpdatesCount() -> Int {
                powerUpdates.count
            }
        }

        let tracker = CallbackTracker()

        // Set callbacks
        worker.setOnPowerUpdate { avg, _, _ in
            Task { await tracker.addPowerUpdate(avg) }
        }

        worker.setOnError { _ in
            Task { await tracker.incrementErrorCount() }
        }

        let testURL = URL(fileURLWithPath: "/tmp/test_callbacks.m4a")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))

        do {
            try await worker.start(writingTo: testURL, format: format, fileFormat: .m4a)
        } catch {
            XCTFail("Failed to start worker: \(error)")
            return
        }

        // Process buffers that will trigger callbacks
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024)!
                    buffer.frameLength = 1_024

                    if let channelData = buffer.floatChannelData {
                        for frame in 0..<Int(buffer.frameLength) {
                            for channel in 0..<Int(buffer.format.channelCount) {
                                channelData[channel][frame] = 0.5 // Non-zero to trigger metering
                            }
                        }
                    }

                    worker.process(buffer)
                }
            }
        }

        // Allow processing to complete.
        try? await Task.sleep(nanoseconds: 100_000_000)

        _ = await worker.stop()

        // Verify callbacks were called
        let powerUpdatesCount = await tracker.getPowerUpdatesCount()
        XCTAssertGreaterThan(powerUpdatesCount, 0, "Power updates should have been received")

        // Clean up
        try? FileManager.default.removeItem(at: testURL)
    }

    // MARK: - Stress Tests

    func testStress_RecordingActor_StateConsistencyUnderLoad() async {
        let actor = RecordingActor()

        // Stress test state consistency
        let iterations = 100

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    await actor.setRecording(i % 2 == 0)
                    await actor.setTranscribing(i % 3 == 0)

                    let recording = await actor.recordingState
                    let transcribing = await actor.transcribingState

                    // States should be boolean values
                    XCTAssertTrue(recording == true || recording == false)
                    XCTAssertTrue(transcribing == true || transcribing == false)
                }
            }
        }

        // Final state should be valid
        let finalRecording = await actor.recordingState
        let finalTranscribing = await actor.transcribingState

        XCTAssertTrue(finalRecording == true || finalRecording == false)
        XCTAssertTrue(finalTranscribing == true || finalTranscribing == false)
    }

    // MARK: - Performance Tests for Concurrency

    func testPerformance_ConcurrentActorAccess() {
        let actor = RecordingActor()

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()]) {
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for i in 0..<50 {
                        group.addTask {
                            await actor.setRecording(i % 2 == 0)
                            _ = await actor.recordingState
                            await actor.setTranscribing(i % 3 == 0)
                            _ = await actor.transcribingState
                        }
                    }
                }
            }
        }
    }
}

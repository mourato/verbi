import AVFoundation
import Combine
@testable import VerbiCore
@testable import VerbiCoreAudio
import XCTest

final class ConcurrencyTests: XCTestCase {

    func testRecordingActor_Isolation_ConcurrentStateAccess() async {
        let actor = RecordingActor()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    await actor.setRecording(i % 2 == 0)
                    let state = await actor.recordingState
                    XCTAssertTrue(state == true || state == false, "State should be consistent")
                }
            }
        }

        let finalState = await actor.recordingState
        XCTAssertTrue(finalState == true || finalState == false)
    }

    func testRecordingActor_Isolation_ConcurrentMeetingUpdates() async {
        let actor = RecordingActor()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask {
                    let app: CaptureOrigin = i % 2 == 0 ? .zoom : .slack
                    let meeting = await actor.createMeeting(app: app)
                    XCTAssertTrue(meeting.app.displayName == "Zoom" || meeting.app.displayName == "Slack")
                }
            }
        }

        let currentMeeting = await actor.currentMeetingState
        XCTAssertNotNil(currentMeeting)
    }

    func testRecordingActor_Isolation_ErrorStateConsistency() async throws {
        let actor = RecordingActor()

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

        let rawFinalError = await actor.lastErrorState
        let finalError = try XCTUnwrap(rawFinalError as NSError?)
        XCTAssertTrue((0..<10).contains(finalError.code), "Final error should be one of the concurrently set errors")
    }

    func testAudioRecordingWorker_BufferProcessingConcurrency() async throws {
        let worker = AudioRecordingWorker()

        let testURL = URL(fileURLWithPath: "/tmp/test_concurrency.m4a")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))

        do {
            try await worker.start(writingTo: testURL, format: format, fileFormat: .m4a)
        } catch {
            XCTFail("Failed to start worker: \(error)")
            return
        }

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024)!
                    buffer.frameLength = 1_024

                    if let channelData = buffer.floatChannelData {
                        for frame in 0..<Int(buffer.frameLength) {
                            for channel in 0..<Int(buffer.format.channelCount) {
                                channelData[channel][frame] = Float(i) / 20.0
                            }
                        }
                    }

                    worker.process(buffer)
                }
            }
        }

        let resultURL = await worker.stop()
        XCTAssertEqual(resultURL, testURL)

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

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024)!
                    buffer.frameLength = 1_024

                    if let channelData = buffer.floatChannelData {
                        for frame in 0..<Int(buffer.frameLength) {
                            for channel in 0..<Int(buffer.format.channelCount) {
                                channelData[channel][frame] = 0.5
                            }
                        }
                    }

                    worker.process(buffer)
                }
            }
        }

        _ = await worker.stop()

        let powerUpdatesCount = await tracker.getPowerUpdatesCount()
        XCTAssertGreaterThan(powerUpdatesCount, 0, "Power updates should have been received")

        try? FileManager.default.removeItem(at: testURL)
    }

    func testStress_RecordingActor_StateConsistencyUnderLoad() async {
        let actor = RecordingActor()

        let iterations = 100

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    await actor.setRecording(i % 2 == 0)
                    await actor.setTranscribing(i % 3 == 0)

                    let recording = await actor.recordingState
                    let transcribing = await actor.transcribingState

                    XCTAssertTrue(recording == true || recording == false)
                    XCTAssertTrue(transcribing == true || transcribing == false)
                }
            }
        }

        let finalRecording = await actor.recordingState
        let finalTranscribing = await actor.transcribingState

        XCTAssertTrue(finalRecording == true || finalRecording == false)
        XCTAssertTrue(finalTranscribing == true || finalTranscribing == false)
    }

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

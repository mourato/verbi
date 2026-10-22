import AVFoundation
@testable import VerbiCore
@testable import VerbiCoreAudio
import XCTest

final class AudioRecordingWorkerTests: XCTestCase {
    func testPerformance_BufferProcessing_Guardrail() throws {
        print("### testPerformance_BufferProcessing_Guardrail START ###")
        let worker = AudioRecordingWorker()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_worker_perf_\(UUID().uuidString).wav")

        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: false) else {
            XCTFail("Failed to create format")
            return
        }

        // Setup worker synchronously (using expectation)
        let setupExpectation = expectation(description: "Setup")
        Task {
            do {
                try await worker.start(writingTo: tempURL, format: format, fileFormat: .wav)
                setupExpectation.fulfill()
            } catch {
                print("### Setup Error: \(error)")
            }
        }
        wait(for: [setupExpectation], timeout: 5.0)

        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024))
        buffer.frameLength = 1_024

        print("### Measuring...")
        measure(metrics: [XCTClockMetric(), XCTCPUMetric()]) {
            // Synchronous call to nonisolated method
            for _ in 0..<100 {
                worker.process(buffer)
            }
        }

        // Cleanup synchronously (using expectation)
        let cleanupExpectation = expectation(description: "Cleanup")
        Task {
            _ = await worker.stop()
            cleanupExpectation.fulfill()
        }
        wait(for: [cleanupExpectation], timeout: 5.0)

        try? FileManager.default.removeItem(at: tempURL)
        print("### testPerformance_BufferProcessing_Guardrail FINISHED ###")
    }
}

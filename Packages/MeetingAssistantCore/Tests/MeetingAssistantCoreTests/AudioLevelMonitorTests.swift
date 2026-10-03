@testable import MeetingAssistantCoreAudio
import Observation
import Synchronization
import XCTest

@MainActor
final class AudioLevelMonitorTests: XCTestCase {
    func testDefaultSamplingInterval_IsApproximatelySixtyHertz() {
        let monitor = AudioLevelMonitor()

        XCTAssertEqual(monitor.effectiveSamplingInterval, 0.017, accuracy: 0.0_001)
    }

    func testMeterUpdates_NotifyOnlyMeterObservers() {
        let monitor = AudioLevelMonitor()
        let warningChanged = Mutex(false)
        let meterChanged = Mutex(false)

        withObservationTracking {
            _ = monitor.isSilenceWarningVisible
        } onChange: {
            warningChanged.withLock { $0 = true }
        }

        monitor.ingestLevels(averageDB: -20, peakDB: -10)
        XCTAssertFalse(warningChanged.withLock { $0 })

        withObservationTracking {
            _ = monitor.audioMeter
        } onChange: {
            meterChanged.withLock { $0 = true }
        }

        monitor.ingestLevels(averageDB: -30, peakDB: -15)
        XCTAssertTrue(meterChanged.withLock { $0 })
        XCTAssertFalse(warningChanged.withLock { $0 })
    }

    func testIngestLevels_NormalizesDecibelsLinearly() {
        let monitor = AudioLevelMonitor(samplingInterval: 0.03)

        monitor.ingestLevels(averageDB: -60, peakDB: -60)
        XCTAssertEqual(monitor.audioMeter.averagePower, 0.0, accuracy: 0.001)
        XCTAssertEqual(monitor.audioMeter.peakPower, 0.0, accuracy: 0.001)

        monitor.ingestLevels(averageDB: -30, peakDB: -30)
        XCTAssertEqual(monitor.audioMeter.averagePower, 0.5, accuracy: 0.001)
        XCTAssertEqual(monitor.audioMeter.peakPower, 0.5, accuracy: 0.001)

        monitor.ingestLevels(averageDB: 0, peakDB: 0)
        XCTAssertEqual(monitor.audioMeter.averagePower, 1.0, accuracy: 0.001)
        XCTAssertEqual(monitor.audioMeter.peakPower, 1.0, accuracy: 0.001)
    }

    func testIngestLevels_ShowsSilenceWarningAfterConfiguredDuration() {
        let monitor = AudioLevelMonitor(samplingInterval: 1.0)

        for _ in 0..<3 {
            monitor.ingestLevels(averageDB: -80, peakDB: -80, deltaTime: 1.0)
            XCTAssertFalse(monitor.isSilenceWarningVisible)
        }

        monitor.ingestLevels(averageDB: -80, peakDB: -80, deltaTime: 1.0)
        XCTAssertTrue(monitor.isSilenceWarningVisible)
    }

    func testIngestLevels_DoesNotShowSilenceWarningOutsideStartupWindow() {
        let monitor = AudioLevelMonitor(samplingInterval: 1.0)

        for _ in 0..<10 {
            monitor.ingestLevels(averageDB: -6, peakDB: -6, deltaTime: 1.0)
        }

        for _ in 0..<8 {
            monitor.ingestLevels(averageDB: -80, peakDB: -80, deltaTime: 1.0)
        }

        XCTAssertFalse(monitor.isSilenceWarningVisible)
    }

    func testDismissSilenceWarning_DoesNotRetriggerInSameSession() {
        let monitor = AudioLevelMonitor(samplingInterval: 1.0)

        for _ in 0..<4 {
            monitor.ingestLevels(averageDB: -80, peakDB: -80, deltaTime: 1.0)
        }
        XCTAssertTrue(monitor.isSilenceWarningVisible)

        monitor.dismissSilenceWarning()
        XCTAssertFalse(monitor.isSilenceWarningVisible)

        for _ in 0..<8 {
            monitor.ingestLevels(averageDB: -80, peakDB: -80, deltaTime: 1.0)
        }
        XCTAssertFalse(monitor.isSilenceWarningVisible)
    }

    func testStopMonitoring_ResetsMeterAndSilenceWarningSessionState() {
        let monitor = AudioLevelMonitor(samplingInterval: 1.0)

        monitor.ingestLevels(averageDB: -20, peakDB: -10, deltaTime: 1.0)
        XCTAssertNotEqual(monitor.audioMeter, .zero)

        for _ in 0..<4 {
            monitor.ingestLevels(averageDB: -80, peakDB: -80, deltaTime: 1.0)
        }
        XCTAssertTrue(monitor.isSilenceWarningVisible)

        monitor.stopMonitoring()
        XCTAssertEqual(monitor.audioMeter, .zero)

        for _ in 0..<4 {
            monitor.ingestLevels(averageDB: -80, peakDB: -80, deltaTime: 1.0)
        }
        XCTAssertTrue(monitor.isSilenceWarningVisible)
    }
}

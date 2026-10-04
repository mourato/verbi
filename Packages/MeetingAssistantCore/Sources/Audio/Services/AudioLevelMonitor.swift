import Combine
import Foundation
import Observation

/// Represents audio levels for visualization.
public struct AudioMeter: Equatable, Sendable {
    public let averagePower: Double
    public let peakPower: Double

    public init(averagePower: Double, peakPower: Double) {
        self.averagePower = averagePower
        self.peakPower = peakPower
    }

    public static let zero = AudioMeter(averagePower: 0, peakPower: 0)
}

/// Monitors audio levels from RecordingManager and publishes normalized samples for waveform visualization.
@MainActor
@Observable
public final class AudioLevelMonitor {
    // MARK: - Published Properties

    /// Current audio meter levels (0...1 normalized).
    public private(set) var audioMeter: AudioMeter = .zero
    /// Latest 21-band spectrum levels (0...1); empty before first snapshot.
    public private(set) var spectrumLevels: [Float] = []
    /// Whether the monitor detected prolonged silence from the microphone.
    public private(set) var isSilenceWarningVisible = false

    // MARK: - Configuration

    /// Interval for sampling audio levels.
    @ObservationIgnored private let samplingInterval: TimeInterval
    /// Accumulated time spent below the silence threshold.
    @ObservationIgnored private var silenceElapsed: TimeInterval = 0
    /// Elapsed monitoring time for the current recording session.
    @ObservationIgnored private var monitoringElapsed: TimeInterval = 0
    /// Tracks whether the warning has already been presented in the current session.
    @ObservationIgnored private var didPresentSilenceWarningThisSession = false

    private enum Constants {
        static let silenceThresholdDb: Float = -50
        static let silenceDurationSeconds: TimeInterval = 4
        static let silenceWarningStartupWindowSeconds: TimeInterval = 10
        static let meterMinDb: Float = -60
        static let meterMaxDb: Float = 0
    }

    // MARK: - Private State

    @ObservationIgnored private var meterSubscription: AnyCancellable?
    @ObservationIgnored private weak var audioRecorder: AudioRecorder?
    var effectiveSamplingInterval: TimeInterval {
        samplingInterval
    }

    // MARK: - Initialization

    /// Creates a new audio level monitor.
    /// - Parameters:
    ///   - audioRecorder: The AudioRecorder instance to monitor.
    ///   - samplingInterval: How often to sample audio levels. Default: 0.017s (~60Hz).
    public init(
        audioRecorder: AudioRecorder = .shared,
        samplingInterval: TimeInterval = 0.017
    ) {
        self.audioRecorder = audioRecorder
        self.samplingInterval = samplingInterval
    }

    // MARK: - Public API

    /// Start monitoring audio levels.
    /// Called when recording starts.
    public func startMonitoring() {
        resetState()
        meterSubscription?.cancel()
        meterSubscription = audioRecorder?.$latestMeterSnapshot
            .compactMap(\.self)
            .sink { [weak self] snapshot in
                self?.ingestLevels(
                    averageDB: snapshot.averagePowerDB,
                    peakDB: snapshot.peakPowerDB,
                    deltaTime: snapshot.deltaTime,
                    spectrum: snapshot.spectrum
                )
            }
    }

    /// Stop monitoring audio levels.
    /// Called when recording stops.
    public func stopMonitoring() {
        meterSubscription?.cancel()
        meterSubscription = nil
        resetState()
    }

    /// Dismiss the silence warning until silence is detected again.
    public func dismissSilenceWarning() {
        isSilenceWarningVisible = false
        silenceElapsed = 0
        didPresentSilenceWarningThisSession = true
    }

    /// Ingests a pair of dB levels and updates published meter/warning state.
    /// Exposed as internal for deterministic unit testing without audio hardware.
    func ingestLevels(
        averageDB: Float,
        peakDB: Float,
        deltaTime: TimeInterval? = nil,
        spectrum: [Float] = []
    ) {
        let effectiveDelta = max(0.001, deltaTime ?? samplingInterval)
        updateSilenceWarning(with: averageDB, deltaTime: effectiveDelta)

        let normalizedAverage = normalizeDecibels(
            averageDB,
            minDB: Constants.meterMinDb,
            maxDB: Constants.meterMaxDb
        )
        let normalizedPeak = normalizeDecibels(
            peakDB,
            minDB: Constants.meterMinDb,
            maxDB: Constants.meterMaxDb
        )
        audioMeter = AudioMeter(
            averagePower: Double(normalizedAverage),
            peakPower: Double(normalizedPeak)
        )
        spectrumLevels = spectrum
    }

    private func resetState() {
        audioMeter = .zero
        spectrumLevels = []
        isSilenceWarningVisible = false
        silenceElapsed = 0
        monitoringElapsed = 0
        didPresentSilenceWarningThisSession = false
    }

    private func updateSilenceWarning(with averageDB: Float, deltaTime: TimeInterval) {
        monitoringElapsed += deltaTime

        if didPresentSilenceWarningThisSession {
            if averageDB > Constants.silenceThresholdDb, isSilenceWarningVisible {
                isSilenceWarningVisible = false
            }
            silenceElapsed = 0
            return
        }

        guard monitoringElapsed <= Constants.silenceWarningStartupWindowSeconds else {
            silenceElapsed = 0
            if isSilenceWarningVisible {
                isSilenceWarningVisible = false
            }
            return
        }

        if averageDB <= Constants.silenceThresholdDb {
            silenceElapsed += deltaTime
            if silenceElapsed >= Constants.silenceDurationSeconds, !isSilenceWarningVisible {
                isSilenceWarningVisible = true
                didPresentSilenceWarningThisSession = true
            }
        } else {
            silenceElapsed = 0
            if isSilenceWarningVisible {
                isSilenceWarningVisible = false
            }
        }
    }

    /// Normalizes a decibel value to the 0...1 range.
    private func normalizeDecibels(_ db: Float, minDB: Float, maxDB: Float) -> Float {
        if db < minDB {
            0.0
        } else if db >= maxDB {
            1.0
        } else {
            (db - minDB) / (maxDB - minDB)
        }
    }
}

import Combine
import Foundation
import Observation

public struct AudioMeter: Equatable, Sendable {
    public let averagePower: Double
    public let peakPower: Double

    public init(averagePower: Double, peakPower: Double) {
        self.averagePower = averagePower
        self.peakPower = peakPower
    }

    public static let zero = AudioMeter(averagePower: 0, peakPower: 0)
}

@MainActor
@Observable
public final class AudioLevelMonitor {
    public private(set) var audioMeter: AudioMeter = .zero
    public private(set) var spectrumLevels: [Float] = []
    public private(set) var isSilenceWarningVisible = false

    @ObservationIgnored private let samplingInterval: TimeInterval
    @ObservationIgnored private var silenceElapsed: TimeInterval = 0
    @ObservationIgnored private var monitoringElapsed: TimeInterval = 0
    @ObservationIgnored private var didPresentSilenceWarningThisSession = false

    private enum Constants {
        static let silenceThresholdDb: Float = -50
        static let silenceDurationSeconds: TimeInterval = 4
        static let silenceWarningStartupWindowSeconds: TimeInterval = 10
        static let meterMinDb: Float = -60
        static let meterMaxDb: Float = 0
    }

    @ObservationIgnored private var meterSubscription: AnyCancellable?
    @ObservationIgnored private weak var audioRecorder: AudioRecorder?
    var effectiveSamplingInterval: TimeInterval {
        samplingInterval
    }

    public init(
        audioRecorder: AudioRecorder = .shared,
        samplingInterval: TimeInterval = 0.017
    ) {
        self.audioRecorder = audioRecorder
        self.samplingInterval = samplingInterval
    }

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

    public func stopMonitoring() {
        meterSubscription?.cancel()
        meterSubscription = nil
        resetState()
    }

    public func dismissSilenceWarning() {
        isSilenceWarningVisible = false
        silenceElapsed = 0
        didPresentSilenceWarningThisSession = true
    }

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
        spectrumLevels = Self.smoothedSpectrum(previous: spectrumLevels, target: spectrum)
    }

    static func smoothedSpectrum(previous: [Float], target: [Float]) -> [Float] {
        guard previous.count == target.count else { return target }
        return zip(previous, target).map { current, next in
            let response: Float = next > current ? 0.6 : 0.25
            return current + (next - current) * response
        }
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

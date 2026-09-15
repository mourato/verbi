import Combine
import Foundation

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

struct CanonicalWaveformFrame: Equatable {
    let timestamp: TimeInterval
    let normalizedLevel: Double
}

/// Monitors audio levels from RecordingManager and publishes normalized samples for waveform visualization.
@MainActor
public final class AudioLevelMonitor: ObservableObject {
    // MARK: - Published Properties

    /// Current audio meter levels (0...1 normalized).
    @Published public private(set) var audioMeter: AudioMeter = .zero
    /// High-resolution canonical envelope derived from the most recent capture window.
    @Published public private(set) var canonicalEnvelopeLevels: [Double] = []
    /// Backward-compatible alias for the canonical envelope.
    @Published public private(set) var instantBarLevels: [Double] = []
    /// Backward-compatible alias for `instantBarLevels`.
    @Published public private(set) var recentAverageLevels: [Double] = []
    /// Whether the monitor detected prolonged silence from the microphone.
    @Published public private(set) var isSilenceWarningVisible = false

    // MARK: - Configuration

    /// Interval for sampling audio levels.
    private let samplingInterval: TimeInterval
    /// Sliding window duration used to build the canonical envelope.
    private let windowDuration: TimeInterval
    /// Accumulated time spent below the silence threshold.
    private var silenceElapsed: TimeInterval = 0
    /// Elapsed monitoring time for the current recording session.
    private var monitoringElapsed: TimeInterval = 0
    /// Tracks whether the warning has already been presented in the current session.
    private var didPresentSilenceWarningThisSession = false

    private enum Constants {
        static let silenceThresholdDb: Float = -50
        static let silenceDurationSeconds: TimeInterval = 4
        static let silenceWarningStartupWindowSeconds: TimeInterval = 10
        static let meterMinDb: Float = -60
        static let meterMaxDb: Float = 0
        static let canonicalResolution = 48
        static let peakBlend = 0.22
        static let attackBlend = 0.78
        static let decayBlend = 0.18
        static let adaptiveScaleBlend = 0.12
        static let minimumAdaptiveScale = 0.24
        static let gateThreshold = 0.11
        static let gateKnee = 0.12
        static let centerBiasEdgeFloor = 0.38
        static let centerBiasExponent = 1.45
        static let symmetryBlend = 0.58
        static let projectionLeftPhaseOffset = 0.11
        static let projectionRightPhaseOffset = 0.59
    }

    // MARK: - Private State

    private var meterSubscription: AnyCancellable?
    private weak var audioRecorder: AudioRecorder?
    private var canonicalFrames: [CanonicalWaveformFrame] = []
    private var waveformClock: TimeInterval = 0
    private var lastEnvelopeLevel: Double = 0
    private var adaptiveScale: Double = Constants.minimumAdaptiveScale

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
        samplingInterval: TimeInterval = 0.017,
        windowDuration: TimeInterval = 0.5
    ) {
        self.audioRecorder = audioRecorder
        self.samplingInterval = samplingInterval
        self.windowDuration = windowDuration
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
                    barLevelsDB: snapshot.barPowerDBLevels,
                    deltaTime: snapshot.deltaTime
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
        barLevelsDB: [Float] = [],
        deltaTime: TimeInterval? = nil
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
        let normalizedBars = barLevelsDB.map {
            Double(normalizeDecibels($0, minDB: Constants.meterMinDb, maxDB: Constants.meterMaxDb))
        }

        audioMeter = AudioMeter(
            averagePower: Double(normalizedAverage),
            peakPower: Double(normalizedPeak)
        )

        let blendedTargetLevel = blendedEnvelopeLevel(
            average: Double(normalizedAverage),
            peak: Double(normalizedPeak)
        )
        let sourceLevel = normalizedBars.isEmpty
            ? blendedTargetLevel
            : normalizedBars.reduce(0, +) / Double(normalizedBars.count)
        let smoothedLevel = smoothedEnvelopeLevel(target: sourceLevel)

        waveformClock += effectiveDelta
        canonicalFrames.append(
            CanonicalWaveformFrame(
                timestamp: waveformClock,
                normalizedLevel: smoothedLevel
            )
        )
        trimCanonicalFrames(now: waveformClock)
        rebuildCanonicalEnvelope()
    }

    public func displayLevels(for barCount: Int) -> [Double] {
        guard barCount > 0 else { return [] }
        guard !canonicalEnvelopeLevels.isEmpty else { return Array(repeating: 0.0, count: barCount) }

        if barCount == 1 {
            return [canonicalEnvelopeLevels.max() ?? 0.0]
        }

        let pairCount = barCount / 2
        let leftSeed = phasedProjection(
            from: canonicalEnvelopeLevels,
            count: pairCount,
            phaseOffset: Constants.projectionLeftPhaseOffset
        )
        let rightSeed = phasedProjection(
            from: canonicalEnvelopeLevels,
            count: pairCount,
            phaseOffset: Constants.projectionRightPhaseOffset
        )

        let mirroredPairs = zip(leftSeed, rightSeed).enumerated().map { index, pair -> (Double, Double) in
            let shared = (pair.0 + pair.1) / 2.0
            let proximityToCenter = pairCount > 1
                ? Double(index) / Double(pairCount - 1)
                : 1.0
            let centerBias = Constants.centerBiasEdgeFloor
                + (1.0 - Constants.centerBiasEdgeFloor) * pow(proximityToCenter, Constants.centerBiasExponent)
            let left = lerp(pair.0, shared, t: Constants.symmetryBlend) * centerBias
            let right = lerp(pair.1, shared, t: Constants.symmetryBlend) * centerBias
            return (min(max(left, 0.0), 1.0), min(max(right, 0.0), 1.0))
        }

        let leftLevels = mirroredPairs.map(\.0)
        let rightLevels = Array(mirroredPairs.map(\.1).reversed())
        let centerSeed = ((leftSeed.last ?? 0.0) + (rightSeed.last ?? 0.0)) / 2.0
        let centerLevel = barCount.isMultiple(of: 2)
            ? []
            : [min(max(centerSeed, 0.0), 1.0)]

        return leftLevels + centerLevel + rightLevels
    }

    private func resetState() {
        audioMeter = .zero
        canonicalEnvelopeLevels = []
        instantBarLevels = []
        recentAverageLevels = []
        isSilenceWarningVisible = false
        silenceElapsed = 0
        monitoringElapsed = 0
        didPresentSilenceWarningThisSession = false
        canonicalFrames = []
        waveformClock = 0
        lastEnvelopeLevel = 0
        adaptiveScale = Constants.minimumAdaptiveScale
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

    private func blendedEnvelopeLevel(average: Double, peak: Double) -> Double {
        let blended = (average * (1.0 - Constants.peakBlend)) + (peak * Constants.peakBlend)
        return min(max(blended, 0.0), 1.0)
    }

    private func smoothedEnvelopeLevel(target: Double) -> Double {
        let blend = target >= lastEnvelopeLevel ? Constants.attackBlend : Constants.decayBlend
        let next = lastEnvelopeLevel + ((target - lastEnvelopeLevel) * blend)
        lastEnvelopeLevel = min(max(next, 0.0), 1.0)
        return lastEnvelopeLevel
    }

    private func trimCanonicalFrames(now: TimeInterval) {
        let cutoff = now - windowDuration
        canonicalFrames.removeAll { $0.timestamp < cutoff }
    }

    private func rebuildCanonicalEnvelope() {
        guard !canonicalFrames.isEmpty else {
            canonicalEnvelopeLevels = []
            instantBarLevels = []
            recentAverageLevels = []
            return
        }

        let sampledLevels = resample(canonicalFrames.map(\.normalizedLevel), count: Constants.canonicalResolution)
        let targetScale = max(Constants.minimumAdaptiveScale, sampledLevels.max() ?? 0.0)
        adaptiveScale = lerp(adaptiveScale, targetScale, t: Constants.adaptiveScaleBlend)
        let normalizedEnvelope = sampledLevels.map { min(max($0 / max(adaptiveScale, Constants.minimumAdaptiveScale), 0.0), 1.0) }
        let gatedEnvelope = normalizedEnvelope.map(softGatedLevel)

        canonicalEnvelopeLevels = gatedEnvelope
        instantBarLevels = gatedEnvelope
        recentAverageLevels = gatedEnvelope
    }

    private func softGatedLevel(_ level: Double) -> Double {
        let clamped = min(max(level, 0.0), 1.0)
        let start = max(0.0, Constants.gateThreshold - Constants.gateKnee)
        let end = min(1.0, Constants.gateThreshold + Constants.gateKnee)
        guard end > start else { return clamped }
        guard clamped > start else { return 0.0 }
        guard clamped < end else { return clamped }

        let progress = (clamped - start) / (end - start)
        let smoothed = progress * progress * (3.0 - (2.0 * progress))
        return clamped * smoothed
    }

    private func phasedProjection(from levels: [Double], count: Int, phaseOffset: Double) -> [Double] {
        guard count > 0 else { return [] }
        guard !levels.isEmpty else { return Array(repeating: 0.0, count: count) }
        guard levels.count > 1 else { return Array(repeating: levels[0], count: count) }

        let maxIndex = Double(levels.count - 1)
        return (0 ..< count).map { index in
            let progress = count > 1 ? Double(index) / Double(count - 1) : 0.5
            let phased = (progress + phaseOffset).truncatingRemainder(dividingBy: 1.0)
            return interpolatedSample(levels, position: phased * maxIndex)
        }
    }

    private func resample(_ levels: [Double], count: Int) -> [Double] {
        guard count > 0 else { return [] }
        guard !levels.isEmpty else { return Array(repeating: 0.0, count: count) }
        guard levels.count > 1 else { return Array(repeating: levels[0], count: count) }

        let maxIndex = Double(levels.count - 1)
        return (0 ..< count).map { index in
            let progress = count > 1 ? Double(index) / Double(count - 1) : 0
            return interpolatedSample(levels, position: progress * maxIndex)
        }
    }

    private func interpolatedSample(_ levels: [Double], position: Double) -> Double {
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = min(levels.count - 1, lowerIndex + 1)
        guard lowerIndex != upperIndex else { return levels[lowerIndex] }
        let fraction = position - Double(lowerIndex)
        return lerp(levels[lowerIndex], levels[upperIndex], t: fraction)
    }

    private func lerp(_ start: Double, _ end: Double, t: Double) -> Double {
        start + ((end - start) * t)
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

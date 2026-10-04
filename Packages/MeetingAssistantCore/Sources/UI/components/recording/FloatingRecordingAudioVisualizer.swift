import MeetingAssistantCoreAudio
import SwiftUI

// MARK: - Audio Visualizer

enum AudioVisualizerMath {
    static func barHeight(level: Double, minHeight: CGFloat, maxHeight: CGFloat) -> CGFloat {
        let effectiveLevel = min(max(level, 0.0), 1.0)
        return minHeight + CGFloat(effectiveLevel) * (maxHeight - minHeight)
    }

    static func typeWhisperWaveformLevels(
        audioLevel: Double,
        barCount: Int,
        isAnimationActive: Bool
    ) -> [Double] {
        guard barCount > 0 else { return [] }
        guard isAnimationActive else { return Array(repeating: 0.0, count: barCount) }

        let clampedLevel = min(max(audioLevel, 0.0), 1.0)
        let maxBarCount = max(barCount, 1)

        return (0 ..< barCount).map { index in
            let phase = Double(index) / Double(maxBarCount) * .pi * 2.0
            let waveOffset = sin(phase + .pi * 0.75 + clampedLevel * 3.0) * 0.12 + 0.88
            var barLevel = clampedLevel * waveOffset

            if index == 0 {
                barLevel *= 0.85
            }

            return min(max(barLevel, 0.0), 1.0)
        }
    }

    /// Processing bars use this share of the height range, keeping the sweep
    /// visibly calmer than live speech (reference: 9pt of 25pt).
    static let processingHeightScale = 9.0 / 25.0

    /// Averages real spectrum bands into bars with edge taper so end bars sit lower.
    /// Falls back to the synthetic wave when `spectrum` is empty (no data yet).
    static func spectrumBarLevels(
        spectrum: [Float],
        barCount: Int,
        isAnimationActive: Bool
    ) -> [Double] {
        guard barCount > 0 else { return [] }
        guard isAnimationActive, !spectrum.isEmpty else { return Array(repeating: 0.0, count: barCount) }

        return (0 ..< barCount).map { index in
            let lower = min(spectrum.count - 1, index * spectrum.count / barCount)
            let upper = max(lower + 1, min(spectrum.count, (index + 1) * spectrum.count / barCount))
            let mean = spectrum[lower ..< upper].reduce(0, +) / Float(upper - lower)
            let edge = min(1.0, Double(min(index, barCount - 1 - index)) / taperSpan(barCount: barCount))
            let taper = edge * edge * (3 - 2 * edge)
            let level = Double(mean) * (0.2 + 0.8 * taper)
            return min(max(level, 0.0), 1.0)
        }
    }

    /// Position emphasis driving bar opacity while listening: edges dim.
    static func barEmphasis(index: Int, barCount: Int) -> Double {
        guard barCount > 0 else { return 0 }
        let clamped = min(max(index, 0), barCount - 1)
        let span = max(1, Double(barCount) * 3 / 21)
        return min(1, Double(min(clamped, barCount - 1 - clamped)) / span)
    }

    /// Edge taper reaches full height 4 bars in at the reference 21 bars;
    /// scaled so other counts keep the same flat-center proportion.
    private static func taperSpan(barCount: Int) -> Double {
        max(1, Double(barCount) * 4 / 21)
    }

    /// Traveling triangular bump for the processing state. Radius and
    /// overscan scale with bar count to keep the reference proportion
    /// (radius 4 of 21 bars, entering and leaving fully off-screen).
    static func processingSweepLevels(progress: Double, barCount: Int) -> [Double] {
        guard barCount > 0 else { return [] }
        let radius = Double(barCount) * 4 / 21
        let center = progress * (Double(barCount - 1) + 2 * radius) - radius
        return (0 ..< barCount).map { index in
            max(0, 1 - abs(Double(index) - center) / radius)
        }
    }
}

struct LiveAudioVisualizer: View {
    let monitor: AudioLevelMonitor
    let isAnimationActive: Bool
    let isSetup: Bool
    let metrics: RecordingWaveMetrics

    var body: some View {
        AudioVisualizer(
            audioLevel: monitor.audioMeter.averagePower,
            spectrum: monitor.spectrumLevels,
            isAnimationActive: isAnimationActive,
            isSetup: isSetup,
            barCount: metrics.barCount,
            maxHeight: metrics.height,
            barWidth: metrics.barWidth,
            barSpacing: metrics.barSpacing,
            barCornerRadius: metrics.barCornerRadius,
            minHeight: AppDesignSystem.Layout.recordingIndicatorWaveformMinHeight
        )
    }
}

struct AudioVisualizer: View {
    let audioLevel: Double
    let spectrum: [Float]
    let isAnimationActive: Bool
    let isSetup: Bool
    let barCount: Int
    let maxHeight: CGFloat
    let barWidth: CGFloat
    let barSpacing: CGFloat
    let barCornerRadius: CGFloat
    let minHeight: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        audioLevel: Double = 0.0,
        spectrum: [Float] = [],
        isAnimationActive: Bool = true,
        isSetup: Bool = false,
        barCount: Int,
        maxHeight: CGFloat,
        barWidth: CGFloat = 4,
        barSpacing: CGFloat = 2,
        barCornerRadius: CGFloat = 1.5,
        minHeight: CGFloat = 8
    ) {
        self.audioLevel = audioLevel
        self.spectrum = spectrum
        self.isAnimationActive = isAnimationActive
        self.isSetup = isSetup
        self.barCount = barCount
        self.maxHeight = maxHeight
        self.barWidth = barWidth
        self.barSpacing = barSpacing
        self.barCornerRadius = barCornerRadius
        self.minHeight = minHeight
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.06, paused: !isBounceActive)) { context in
            let bounceIndex = isBounceActive
                ? Int(context.date.timeIntervalSinceReferenceDate / 0.06) % max(barCount, 1)
                : 0
            let levels = if isSetup {
                bounceLevels(at: bounceIndex)
            } else if !spectrum.isEmpty {
                AudioVisualizerMath.spectrumBarLevels(
                    spectrum: spectrum,
                    barCount: barCount,
                    isAnimationActive: isAnimationActive
                )
            } else {
                AudioVisualizerMath.typeWhisperWaveformLevels(
                    audioLevel: audioLevel,
                    barCount: barCount,
                    isAnimationActive: isAnimationActive
                )
            }

            HStack(spacing: barSpacing) {
                ForEach(0 ..< barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: barCornerRadius)
                        .fill(Color.white)
                        .opacity(0.4 + 0.6 * AudioVisualizerMath.barEmphasis(index: index, barCount: barCount))
                        .frame(
                            width: barWidth,
                            height: AudioVisualizerMath.barHeight(
                                level: levels[safe: index] ?? 0.0,
                                minHeight: minHeight,
                                maxHeight: maxHeight
                            )
                        )
                        .animation(isSetup ? setupBounceAnimation : nil, value: bounceIndex)
                }
            }
            .frame(height: maxHeight, alignment: .center)
            .animation(isSetup ? nil : .easeOut(duration: 0.06), value: levels)
        }
    }

    private var isBounceActive: Bool {
        isSetup && isAnimationActive && !reduceMotion
    }

    private var setupBounceAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.3)
    }

    private func bounceLevels(at bounceIndex: Int) -> [Double] {
        guard barCount > 0 else { return [] }
        let bounceLevel = max(0.0, min(1.0, (14.0 - minHeight) / max(maxHeight - minHeight, 0.000_001)))
        return (0 ..< barCount).map { index in
            index == bounceIndex ? bounceLevel : 0.0
        }
    }
}

/// Traveling sweep shown while processing. Freezes mid-sweep under
/// Reduce Motion, matching the reference fallback.
struct ProcessingSweepWave: View {
    let barCount: Int
    let maxHeight: CGFloat
    let barWidth: CGFloat
    let barSpacing: CGFloat
    let barCornerRadius: CGFloat
    let minHeight: CGFloat
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isSweepRunning)) { timeline in
            let progress = isSweepRunning
                ? timeline.date.timeIntervalSince(startedAt).truncatingRemainder(dividingBy: 1.2) / 1.2
                : 0.5
            let levels = AudioVisualizerMath.processingSweepLevels(progress: progress, barCount: barCount)

            HStack(spacing: barSpacing) {
                ForEach(0 ..< barCount, id: \.self) { index in
                    let level = levels[safe: index] ?? 0.0
                    RoundedRectangle(cornerRadius: barCornerRadius)
                        .fill(Color.white)
                        .opacity(0.4 + 0.6 * level)
                        .frame(
                            width: barWidth,
                            height: AudioVisualizerMath.barHeight(
                                level: level * AudioVisualizerMath.processingHeightScale,
                                minHeight: minHeight,
                                maxHeight: maxHeight
                            )
                        )
                }
            }
            .frame(height: maxHeight, alignment: .center)
            .animation(.easeOut(duration: 0.06), value: levels)
        }
    }

    private var isSweepRunning: Bool {
        isActive && !reduceMotion
    }
}

private struct AudioVisualizerLivePreview: View {
    var body: some View {
        AudioVisualizer(
            audioLevel: 0.62,
            isAnimationActive: true,
            barCount: AppDesignSystem.Layout.recordingIndicatorClassicWaveCount,
            maxHeight: AppDesignSystem.Layout.recordingIndicatorClassicWaveHeight,
            barWidth: AppDesignSystem.Layout.recordingIndicatorWaveformBarWidth,
            barSpacing: AppDesignSystem.Layout.recordingIndicatorWaveformBarSpacing,
            barCornerRadius: 1.5,
            minHeight: AppDesignSystem.Layout.recordingIndicatorWaveformMinHeight
        )
        .padding()
        .background(AppDesignSystem.Colors.neutral.opacity(0.8))
    }
}

#Preview("Recording Audio Visualizer", traits: .sizeThatFitsLayout) {
    AudioVisualizerLivePreview()
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

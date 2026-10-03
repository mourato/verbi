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
}

struct LiveAudioVisualizer: View {
    let monitor: AudioLevelMonitor
    let isAnimationActive: Bool
    let isSetup: Bool
    let metrics: RecordingWaveMetrics

    var body: some View {
        AudioVisualizer(
            audioLevel: monitor.audioMeter.averagePower,
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
            let levels = isSetup ? bounceLevels(at: bounceIndex) : AudioVisualizerMath.typeWhisperWaveformLevels(
                audioLevel: audioLevel,
                barCount: barCount,
                isAnimationActive: isAnimationActive
            )

            HStack(spacing: barSpacing) {
                ForEach(0 ..< barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: barCornerRadius)
                        .fill(Color.white)
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

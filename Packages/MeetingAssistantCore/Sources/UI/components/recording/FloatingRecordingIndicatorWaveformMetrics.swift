import CoreGraphics

struct RecordingWaveMetrics {
    let barCount: Int
    let height: CGFloat
    let barWidth: CGFloat
    let barSpacing: CGFloat
    let barCornerRadius: CGFloat
}

enum RecordingWaveMetricsProvider {
    private static let typeWhisperWaveformCornerRadius: CGFloat = 1.5

    static func metrics(
        for size: FloatingRecordingIndicatorView.IndicatorSize
    ) -> RecordingWaveMetrics {
        switch size {
        case .classic:
            RecordingWaveMetrics(
                barCount: AppDesignSystem.Layout.recordingIndicatorClassicWaveCount,
                height: AppDesignSystem.Layout.recordingIndicatorClassicWaveHeight,
                barWidth: AppDesignSystem.Layout.recordingIndicatorWaveformBarWidth,
                barSpacing: AppDesignSystem.Layout.recordingIndicatorWaveformBarSpacing,
                barCornerRadius: typeWhisperWaveformCornerRadius
            )
        case .mini:
            RecordingWaveMetrics(
                barCount: AppDesignSystem.Layout.recordingIndicatorMiniWaveCount,
                height: AppDesignSystem.Layout.recordingIndicatorMiniWaveHeight,
                barWidth: AppDesignSystem.Layout.recordingIndicatorWaveformBarWidth,
                barSpacing: AppDesignSystem.Layout.recordingIndicatorWaveformBarSpacing,
                barCornerRadius: typeWhisperWaveformCornerRadius
            )
        case .super:
            RecordingWaveMetrics(
                barCount: AppDesignSystem.Layout.recordingIndicatorSuperWaveCount,
                height: AppDesignSystem.Layout.recordingIndicatorSuperWaveHeight,
                barWidth: AppDesignSystem.Layout.recordingIndicatorSuperWaveformBarWidth,
                barSpacing: AppDesignSystem.Layout.recordingIndicatorSuperWaveformBarSpacing,
                barCornerRadius: typeWhisperWaveformCornerRadius
            )
        }
    }
}

extension FloatingRecordingIndicatorViewUtilities {
    static func waveformHeight(for size: FloatingRecordingIndicatorView.IndicatorSize) -> CGFloat {
        waveformMetrics(for: size).height
    }

    static func waveCount(for size: FloatingRecordingIndicatorView.IndicatorSize) -> Int {
        waveformMetrics(for: size).barCount
    }

    static func waveformMetrics(
        for size: FloatingRecordingIndicatorView.IndicatorSize
    ) -> RecordingWaveMetrics {
        RecordingWaveMetricsProvider.metrics(for: size)
    }

    static func waveformWidth(for size: FloatingRecordingIndicatorView.IndicatorSize) -> CGFloat {
        let metrics = waveformMetrics(for: size)
        let count = CGFloat(metrics.barCount)
        guard count > 0 else { return 0 }

        let totalBarWidth = count * metrics.barWidth
        let totalSpacing = max(0, count - 1) * metrics.barSpacing
        return totalBarWidth + totalSpacing
    }

    static func waveformBarWidth(for size: FloatingRecordingIndicatorView.IndicatorSize) -> CGFloat {
        waveformMetrics(for: size).barWidth
    }

    static func waveformBarSpacing(for size: FloatingRecordingIndicatorView.IndicatorSize) -> CGFloat {
        waveformMetrics(for: size).barSpacing
    }
}

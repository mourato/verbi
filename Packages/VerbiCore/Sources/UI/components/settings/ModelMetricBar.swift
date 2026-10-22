import SwiftUI
import VerbiCoreCommon

/// Five-segment bar showing a metric relative to the best value in the current list.
struct ModelMetricBar: View {
    static let segmentCount = 5

    /// Value relative to the best entry, `0...1`.
    let fraction: Double
    let label: String

    /// Filled segments for a fraction; any positive value fills at least one segment.
    static func filledSegments(for fraction: Double) -> Int {
        guard fraction.isFinite, fraction > 0 else { return 0 }
        return min(segmentCount, max(1, Int((min(1, fraction) * Double(segmentCount)).rounded())))
    }

    /// `value / best`, clamped to `0...1`; `0` when no positive best exists.
    static func fraction(_ value: Double, best: Double) -> Double {
        guard best.isFinite, best > 0, value.isFinite else { return 0 }
        return min(1, max(0, value / best))
    }

    var body: some View {
        let filled = Self.filledSegments(for: fraction)
        HStack(spacing: 2) {
            ForEach(0 ..< Self.segmentCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(index < filled ? AppDesignSystem.Colors.accent : AppDesignSystem.Colors.subtleFill)
                    .frame(width: 4, height: 10)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
    }
}

#Preview("Metric bar") {
    VStack(alignment: .trailing, spacing: 8) {
        ModelMetricBar(fraction: 1, label: "Speed")
        ModelMetricBar(fraction: 0.62, label: "Speed")
        ModelMetricBar(fraction: 0.05, label: "Speed")
        ModelMetricBar(fraction: 0, label: "Speed")
    }
    .padding()
}

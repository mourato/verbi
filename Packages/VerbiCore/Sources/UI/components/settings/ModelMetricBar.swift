import SwiftUI
import VerbiCoreCommon

struct ModelMetricBar: View {
    static let segmentCount = 5

    let fraction: Double
    let label: String

    static func filledSegments(for fraction: Double) -> Int {
        guard fraction.isFinite, fraction > 0 else { return 0 }
        return min(segmentCount, max(1, Int((min(1, fraction) * Double(segmentCount)).rounded())))
    }

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

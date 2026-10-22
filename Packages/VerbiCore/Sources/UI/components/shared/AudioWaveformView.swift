import SwiftUI

// MARK: - Model

/// Represents a single bar in the waveform visualization.
private struct WaveformBar: Identifiable {
    let id: Int
    let normalizedAmplitude: Float
    let relativePosition: Double
}

// MARK: - View

/// A simple bar-based waveform visualization.
public struct AudioWaveformView: View {
    private enum Layout {
        static let barWidth: CGFloat = 2
        static let minimumBarHeight: CGFloat = 1
    }

    let samples: [Float]
    let progress: Double
    let color: Color

    public init(samples: [Float], progress: Double, color: Color = .accentColor) {
        self.samples = samples
        self.progress = progress
        self.color = color
    }

    private var bars: [WaveformBar] {
        let count = samples.count
        guard count > 0 else { return [] }
        let denominator = max(Double(count - 1), 1)
        return samples.enumerated().map { index, amplitude in
            WaveformBar(
                id: index,
                normalizedAmplitude: amplitude,
                relativePosition: Double(index) / denominator
            )
        }
    }

    public var body: some View {
        GeometryReader { geometry in
            let spacing = barSpacing(for: geometry.size.width)

            HStack(alignment: .center, spacing: spacing) {
                ForEach(bars) { bar in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(bar.relativePosition <= progress ? color : color.opacity(0.3))
                        .frame(width: Layout.barWidth)
                        .frame(
                            height: max(
                                Layout.minimumBarHeight,
                                geometry.size.height * CGFloat(bar.normalizedAmplitude)
                            )
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }

    private func barSpacing(for totalWidth: CGFloat) -> CGFloat {
        let count = bars.count
        guard count > 1 else { return 0 }

        let occupiedWidth = CGFloat(count) * Layout.barWidth
        return max(0, (totalWidth - occupiedWidth) / CGFloat(count - 1))
    }
}

#Preview {
    AudioWaveformView(
        samples: [0.2, 0.4, 0.8, 0.5, 0.3, 0.9, 0.4, 0.2, 0.6, 0.8, 0.2, 0.4, 0.8, 0.5, 0.3, 0.9, 0.4, 0.2, 0.6, 0.8],
        progress: 0.6
    )
    .frame(width: 200, height: 40)
    .padding()
}

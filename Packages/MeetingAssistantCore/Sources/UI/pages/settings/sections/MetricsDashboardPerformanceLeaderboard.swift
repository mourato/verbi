import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

struct PerformanceLeaderboardSection: View {
    let stage: ModelPerformanceStage
    @Binding var sort: LeaderboardSort
    let entries: [ModelPerformanceLeaderboardEntry]

    var body: some View {
        DSGroup("metrics.performance.leaderboard.title".localized, icon: "list.number") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("metrics.performance.leaderboard.subtitle".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    MetricsDashboardFilterMenu(
                        selection: $sort,
                        options: LeaderboardSort.allCases,
                        displayName: \.displayName
                    )
                }

                if entries.isEmpty {
                    Text("metrics.performance.leaderboard.empty".localized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        header

                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            Divider()
                            PerformanceLeaderboardRow(
                                rank: index + 1,
                                stage: stage,
                                entry: entry,
                                bestThroughput: bestThroughput,
                                bestSuccessRate: bestSuccessRate
                            )
                        }
                    }
                }
            }
        }
    }

    private var bestThroughput: Double {
        entries.map(\.normalizedThroughput).max() ?? 0
    }

    private var bestSuccessRate: Double {
        entries.map(\.successRate).max() ?? 0
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("metrics.performance.leaderboard.header.model".localized)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            Text("metrics.performance.leaderboard.header.speed".localized)
                .frame(width: PerformanceLeaderboardColumns.speed, alignment: .trailing)
            Text("metrics.performance.leaderboard.header.latency".localized)
                .frame(width: PerformanceLeaderboardColumns.latency, alignment: .trailing)
            Text("metrics.performance.leaderboard.header.attempts".localized)
                .frame(width: PerformanceLeaderboardColumns.attempts, alignment: .trailing)
            Text("metrics.performance.leaderboard.header.success".localized)
                .frame(width: PerformanceLeaderboardColumns.success, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private enum PerformanceLeaderboardColumns {
    static let rank: CGFloat = 24
    static let speed: CGFloat = 120
    static let latency: CGFloat = 80
    static let attempts: CGFloat = 64
    static let success: CGFloat = 96
}

private struct PerformanceLeaderboardRow: View {
    let rank: Int
    let stage: ModelPerformanceStage
    let entry: ModelPerformanceLeaderboardEntry
    let bestThroughput: Double
    let bestSuccessRate: Double

    var body: some View {
        let identity = ModelPerformanceDisplayIdentity(entry.identity, stage: stage)

        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text("\(rank)")
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .frame(width: PerformanceLeaderboardColumns.rank, alignment: .leading)

                ModelIdentityView(
                    title: identity.title,
                    subtitle: identity.providerName,
                    brand: identity.brand,
                    host: identity.host,
                    fallbackSymbolName: identity.fallbackSymbolName,
                    size: .compact
                )

                if entry.isBestBalance {
                    Text("metrics.performance.badge.best_balance".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    ModelMetricBar(
                        fraction: ModelMetricBar.fraction(entry.normalizedThroughput, best: bestThroughput),
                        label: "metrics.performance.leaderboard.header.speed".localized
                    )
                    .accessibilityHidden(true)
                    Text(ModelPerformanceFormatting.throughput(entry.normalizedThroughput, stage: stage))
                }
                Text(ModelPerformanceFormatting.secondaryThroughput(entry.secondaryThroughput, stage: stage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: PerformanceLeaderboardColumns.speed, alignment: .trailing)

            Text(ModelPerformanceFormatting.duration(entry.medianWallClockSeconds))
                .frame(width: PerformanceLeaderboardColumns.latency, alignment: .trailing)

            Text("\(entry.attemptCount)")
                .frame(width: PerformanceLeaderboardColumns.attempts, alignment: .trailing)

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    ModelMetricBar(
                        fraction: ModelMetricBar.fraction(entry.successRate, best: bestSuccessRate),
                        label: "metrics.performance.leaderboard.header.success".localized
                    )
                    .accessibilityHidden(true)
                    Text(ModelPerformanceFormatting.percent(entry.successRate))
                }
                Text("\(entry.failedAttempts) " + "metrics.performance.summary.failures".localized)
                    .font(.caption)
                    .foregroundStyle(entry.failedAttempts > 0 ? AppDesignSystem.Colors.error : .secondary)
            }
            .frame(width: PerformanceLeaderboardColumns.success, alignment: .trailing)
        }
        .font(.callout)
        .monospacedDigit()
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Performance leaderboard") {
    let entries = [
        ModelPerformanceLeaderboardEntry(
            identity: TranscriptionProvider.groq.modelPerformanceIdentity(modelID: "whisper-large-v3-turbo"),
            attemptCount: 42, successfulAttempts: 41, failedAttempts: 1, successRate: 41.0 / 42.0,
            medianWallClockSeconds: 3.2, averageWallClockSeconds: 3.6,
            normalizedThroughput: 48.5, secondaryThroughput: 48.5, isBestBalance: true
        ),
        ModelPerformanceLeaderboardEntry(
            identity: TranscriptionProvider.local.modelPerformanceIdentity(modelID: TranscriptionProvider.localModelID),
            attemptCount: 18, successfulAttempts: 15, failedAttempts: 3, successRate: 15.0 / 18.0,
            medianWallClockSeconds: 11.4, averageWallClockSeconds: 12.0,
            normalizedThroughput: 14.2, secondaryThroughput: 14.2, isBestBalance: false
        )
    ]
    PerformanceLeaderboardSection(stage: .transcription, sort: .constant(.bestBalance), entries: entries)
        .padding()
        .frame(width: 720)
}

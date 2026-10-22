import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import SwiftUI

// preview-check: ignore — composed by the performance dashboard route previews.

struct PerformanceHistorySection: View {
    let stage: ModelPerformanceStage
    let attempts: [ModelPerformanceAttempt]
    let openRecording: (UUID) -> Void

    var body: some View {
        DSGroup("metrics.performance.history.title".localized, icon: "clock.arrow.trianglehead.counterclockwise.rotate.90") {
            VStack(alignment: .leading, spacing: 12) {
                Text("metrics.performance.history.subtitle".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if attempts.isEmpty {
                    Text("metrics.performance.history.empty".localized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(attempts) { attempt in
                            MetricsDashboardPerformanceHistoryRow(
                                stage: stage,
                                attempt: attempt,
                                openRecording: openRecording
                            )

                            if attempt.id != attempts.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct MetricsDashboardPerformanceHistoryRow: View {
    let stage: ModelPerformanceStage
    let attempt: ModelPerformanceAttempt
    let openRecording: (UUID) -> Void

    var body: some View {
        let identity = ModelPerformanceDisplayIdentity(attempt.modelIdentity, stage: stage)

        HStack(alignment: .top, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ModelPerformanceFormatting.dateTime(attempt.startedAt))
                        .monospacedDigit()

                    Text(attempt.attemptKind.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 160, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    ModelIdentityView(
                        title: identity.title,
                        brand: identity.brand,
                        fallbackSymbolName: identity.fallbackSymbolName,
                        size: .inline
                    )

                    Text("\(identity.providerName) • \(attempt.modelIdentity.runtimeKind.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let failureReason = attempt.failureReason?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !failureReason.isEmpty
                    {
                        Text(failureReason)
                            .font(.caption)
                            .foregroundStyle(AppDesignSystem.Colors.error)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(ModelPerformanceFormatting.duration(attempt.wallClockSeconds))
                        .monospacedDigit()

                    Text(ModelPerformanceFormatting.attemptInput(attempt, stage: stage))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Text(attempt.status.displayName)
                        .font(.caption)
                        .foregroundStyle(attempt.status == .succeeded ? .secondary : AppDesignSystem.Colors.error)
                }
                .frame(width: 160, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)

            Button("metrics.performance.history.open_recording".localized) {
                openRecording(attempt.transcriptionID)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

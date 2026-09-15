import Foundation

public enum ModelPerformanceAggregator {
    public static func computeAnalysis(
        attempts: [ModelPerformanceAttempt],
        stage: ModelPerformanceStage
    ) -> ModelPerformanceAnalysis {
        let stageAttempts = attempts
            .filter { $0.stage == stage }
            .sorted { $0.startedAt > $1.startedAt }
        let successfulAttempts = stageAttempts.filter { $0.status == .succeeded }
        let grouped = Dictionary(grouping: stageAttempts, by: \.modelIdentity.aggregateKey)

        var leaderboard = grouped.values.map { items in
            makeEntry(items: items, stage: stage)
        }

        leaderboard.sort { lhs, rhs in
            if lhs.successRate != rhs.successRate {
                return lhs.successRate > rhs.successRate
            }
            if lhs.normalizedThroughput != rhs.normalizedThroughput {
                return lhs.normalizedThroughput > rhs.normalizedThroughput
            }
            return lhs.medianWallClockSeconds < rhs.medianWallClockSeconds
        }

        if let bestIndex = leaderboard.firstIndex(where: { $0.attemptCount >= 3 }) {
            let best = leaderboard[bestIndex]
            leaderboard[bestIndex] = ModelPerformanceLeaderboardEntry(
                identity: best.identity,
                attemptCount: best.attemptCount,
                successfulAttempts: best.successfulAttempts,
                failedAttempts: best.failedAttempts,
                successRate: best.successRate,
                medianWallClockSeconds: best.medianWallClockSeconds,
                averageWallClockSeconds: best.averageWallClockSeconds,
                normalizedThroughput: best.normalizedThroughput,
                secondaryThroughput: best.secondaryThroughput,
                isBestBalance: true
            )
        }

        let summary = ModelPerformanceSummary(
            stage: stage,
            totalAttempts: stageAttempts.count,
            successfulAttempts: successfulAttempts.count,
            failedAttempts: stageAttempts.count - successfulAttempts.count,
            distinctModels: grouped.count,
            fastestModelDisplayName: leaderboard.first?.identity.modelDisplayName,
            fastestModelThroughput: leaderboard.first?.normalizedThroughput ?? 0
        )

        let providerIDs = Array(Set(stageAttempts.map(\.modelIdentity.providerID))).sorted()

        return ModelPerformanceAnalysis(
            stage: stage,
            summary: summary,
            leaderboard: leaderboard,
            history: stageAttempts,
            availableProviderIDs: providerIDs
        )
    }

    private static func makeEntry(
        items: [ModelPerformanceAttempt],
        stage: ModelPerformanceStage
    ) -> ModelPerformanceLeaderboardEntry {
        let ordered = items.sorted { $0.startedAt < $1.startedAt }
        let successful = ordered.filter { $0.status == .succeeded }
        let attemptCount = ordered.count
        let successCount = successful.count
        let failureCount = attemptCount - successCount
        let successRate = attemptCount == 0 ? 0 : Double(successCount) / Double(attemptCount)
        let medianWallClock = median(of: successful.map(\.wallClockSeconds))
        let averageWallClock = average(of: successful.map(\.wallClockSeconds))

        let throughputSamples = successful.compactMap { attempt -> Double? in
            guard attempt.wallClockSeconds > 0 else { return nil }
            switch stage {
            case .transcription:
                guard attempt.audioSeconds > 0 else { return nil }
                return attempt.audioSeconds / attempt.wallClockSeconds
            case .postProcessing:
                guard attempt.inputUTF8Bytes > 0 else { return nil }
                return Double(attempt.inputUTF8Bytes) / attempt.wallClockSeconds
            }
        }

        let secondarySamples = successful.compactMap { attempt -> Double? in
            guard attempt.wallClockSeconds > 0 else { return nil }
            switch stage {
            case .transcription:
                guard attempt.audioSeconds > 0 else { return nil }
                return (attempt.audioSeconds / 60.0) / (attempt.wallClockSeconds / 60.0)
            case .postProcessing:
                guard attempt.inputCharacterCount > 0 else { return nil }
                return Double(attempt.inputCharacterCount) / attempt.wallClockSeconds
            }
        }

        return ModelPerformanceLeaderboardEntry(
            identity: ordered.first?.modelIdentity ?? .init(
                providerID: "unknown",
                providerDisplayName: "Unknown",
                modelID: "unknown",
                modelDisplayName: "Unknown",
                runtimeKind: .unknown
            ),
            attemptCount: attemptCount,
            successfulAttempts: successCount,
            failedAttempts: failureCount,
            successRate: successRate,
            medianWallClockSeconds: medianWallClock,
            averageWallClockSeconds: averageWallClock,
            normalizedThroughput: average(of: throughputSamples),
            secondaryThroughput: average(of: secondarySamples),
            isBestBalance: false
        )
    }

    private static func average(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func median(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let midpoint = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[midpoint - 1] + sorted[midpoint]) / 2
        }
        return sorted[midpoint]
    }
}

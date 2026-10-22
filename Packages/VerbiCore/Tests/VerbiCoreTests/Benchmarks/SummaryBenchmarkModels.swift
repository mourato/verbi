import Foundation
@testable import VerbiCoreDomain

enum SummaryBenchmarkGateMode: String, Codable, Equatable {
    case reportOnly = "report-only"
    case enforce
}

struct SummaryBenchmarkFixtureSet: Codable, Equatable {
    let schemaVersion: Int
    let fixtures: [SummaryBenchmarkFixture]
    let rubric: SummaryBenchmarkRubric?
}

struct SummaryBenchmarkFixture: Codable, Equatable {
    let id: String
    let description: String
    let transcript: String
    let providerOutput: String
    let expected: CanonicalSummary
}

struct SummaryBenchmarkRubric: Codable, Equatable {
    let version: Int
    let thresholds: SummaryBenchmarkMetricSet

    static let v1 = SummaryBenchmarkRubric(
        version: 1,
        thresholds: SummaryBenchmarkMetricSet(
            schemaValidityRate: 1.00,
            summaryTokenF1: 0.85,
            keyPointsF1: 0.80,
            decisionsF1: 0.80,
            actionItemsTitleF1: 0.75,
            openQuestionsF1: 0.75,
            trustFlagsAccuracy: 0.90,
            hallucinationRate: 0.15,
        ),
    )
}

struct SummaryBenchmarkMetricSet: Codable, Equatable {
    let schemaValidityRate: Double
    let summaryTokenF1: Double
    let keyPointsF1: Double
    let decisionsF1: Double
    let actionItemsTitleF1: Double
    let openQuestionsF1: Double
    let trustFlagsAccuracy: Double
    let hallucinationRate: Double

    static let zero = SummaryBenchmarkMetricSet(
        schemaValidityRate: 0,
        summaryTokenF1: 0,
        keyPointsF1: 0,
        decisionsF1: 0,
        actionItemsTitleF1: 0,
        openQuestionsF1: 0,
        trustFlagsAccuracy: 0,
        hallucinationRate: 0,
    )
}

struct SummaryBenchmarkResult: Codable, Equatable {
    let schemaVersion: Int
    let generatedAt: Date
    let mode: SummaryBenchmarkGateMode
    let fixtureCount: Int
    let metrics: SummaryBenchmarkMetricSet
    let thresholds: SummaryBenchmarkMetricSet
    let baseline: SummaryBenchmarkMetricSet?
    let thresholdFailures: [String]
    let baselineRegressions: [String]

    var passesEnforcement: Bool {
        thresholdFailures.isEmpty && baselineRegressions.isEmpty
    }
}

struct SummaryBenchmarkBaseline: Codable, Equatable {
    let schemaVersion: Int
    let generatedAt: Date
    let source: String
    let metrics: SummaryBenchmarkMetricSet
}

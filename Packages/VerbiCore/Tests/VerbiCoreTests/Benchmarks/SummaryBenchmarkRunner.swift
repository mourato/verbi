import Foundation
@testable import VerbiCoreAI
@testable import VerbiCoreDomain

enum SummaryBenchmarkRunnerError: Error, Equatable {
    case unsupportedFixtureSchemaVersion(Int)
    case unsupportedRubricVersion(Int)
    case emptyFixtureSet
}

struct SummaryBenchmarkRunner {
    private let parser: CanonicalSummaryResponseParser
    private let nowProvider: () -> Date
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        parser: CanonicalSummaryResponseParser = .init(),
        nowProvider: @escaping () -> Date = Date.init,
    ) {
        self.parser = parser
        self.nowProvider = nowProvider

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    func loadFixtureSet(from url: URL) throws -> SummaryBenchmarkFixtureSet {
        let data = try Data(contentsOf: url)
        let fixtureSet = try decoder.decode(SummaryBenchmarkFixtureSet.self, from: data)

        guard fixtureSet.schemaVersion == CanonicalSummary.currentSchemaVersion else {
            throw SummaryBenchmarkRunnerError.unsupportedFixtureSchemaVersion(fixtureSet.schemaVersion)
        }
        guard !fixtureSet.fixtures.isEmpty else {
            throw SummaryBenchmarkRunnerError.emptyFixtureSet
        }

        if let rubric = fixtureSet.rubric, rubric.version != 1 {
            throw SummaryBenchmarkRunnerError.unsupportedRubricVersion(rubric.version)
        }

        return fixtureSet
    }

    func loadBaseline(from url: URL) throws -> SummaryBenchmarkBaseline {
        let data = try Data(contentsOf: url)
        return try decoder.decode(SummaryBenchmarkBaseline.self, from: data)
    }

    func writeResult(_ result: SummaryBenchmarkResult, to url: URL) throws {
        let parentDirectory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        let data = try encoder.encode(result)
        try data.write(to: url, options: [.atomic])
    }

    func writeBaseline(_ baseline: SummaryBenchmarkBaseline, to url: URL) throws {
        let parentDirectory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        let data = try encoder.encode(baseline)
        try data.write(to: url, options: [.atomic])
    }

    func run(
        fixtureSet: SummaryBenchmarkFixtureSet,
        mode: SummaryBenchmarkGateMode,
        baseline: SummaryBenchmarkBaseline?,
    ) -> SummaryBenchmarkResult {
        let rubric = fixtureSet.rubric ?? .v1
        let fixtureCount = Double(fixtureSet.fixtures.count)

        let aggregate = fixtureSet.fixtures.reduce(into: SummaryBenchmarkMetricSet.zero) { partialResult, fixture in
            let parsedSummary = parseAndValidateSummary(from: fixture.providerOutput)

            let schemaValidity = parsedSummary == nil ? 0.0 : 1.0
            let summaryF1 = fieldF1(predicted: parsedSummary?.summary, expected: fixture.expected.summary)
            let keyPointsF1 = fieldF1(
                predicted: parsedSummary?.keyPoints.joined(separator: " "),
                expected: fixture.expected.keyPoints.joined(separator: " "),
            )
            let decisionsF1 = fieldF1(
                predicted: parsedSummary?.decisions.joined(separator: " "),
                expected: fixture.expected.decisions.joined(separator: " "),
            )
            let actionItemsTitleF1 = fieldF1(
                predicted: parsedSummary?.actionItems.map(\.title).joined(separator: " "),
                expected: fixture.expected.actionItems.map(\.title).joined(separator: " "),
            )
            let openQuestionsF1 = fieldF1(
                predicted: parsedSummary?.openQuestions.joined(separator: " "),
                expected: fixture.expected.openQuestions.joined(separator: " "),
            )
            let trustFlagsAccuracy = trustFlagsAccuracy(predicted: parsedSummary, expected: fixture.expected)
            let hallucinationRate = hallucinationRate(transcript: fixture.transcript, predicted: parsedSummary)

            partialResult = SummaryBenchmarkMetricSet(
                schemaValidityRate: partialResult.schemaValidityRate + schemaValidity,
                summaryTokenF1: partialResult.summaryTokenF1 + summaryF1,
                keyPointsF1: partialResult.keyPointsF1 + keyPointsF1,
                decisionsF1: partialResult.decisionsF1 + decisionsF1,
                actionItemsTitleF1: partialResult.actionItemsTitleF1 + actionItemsTitleF1,
                openQuestionsF1: partialResult.openQuestionsF1 + openQuestionsF1,
                trustFlagsAccuracy: partialResult.trustFlagsAccuracy + trustFlagsAccuracy,
                hallucinationRate: partialResult.hallucinationRate + hallucinationRate,
            )
        }

        let averagedMetrics = SummaryBenchmarkMetricSet(
            schemaValidityRate: aggregate.schemaValidityRate / fixtureCount,
            summaryTokenF1: aggregate.summaryTokenF1 / fixtureCount,
            keyPointsF1: aggregate.keyPointsF1 / fixtureCount,
            decisionsF1: aggregate.decisionsF1 / fixtureCount,
            actionItemsTitleF1: aggregate.actionItemsTitleF1 / fixtureCount,
            openQuestionsF1: aggregate.openQuestionsF1 / fixtureCount,
            trustFlagsAccuracy: aggregate.trustFlagsAccuracy / fixtureCount,
            hallucinationRate: aggregate.hallucinationRate / fixtureCount,
        )

        let thresholdFailures = thresholdFailures(metrics: averagedMetrics, thresholds: rubric.thresholds)
        let baselineRegressions: [String] = if mode == .enforce, let baseline {
            computeBaselineRegressions(current: averagedMetrics, baseline: baseline.metrics)
        } else {
            []
        }

        return SummaryBenchmarkResult(
            schemaVersion: CanonicalSummary.currentSchemaVersion,
            generatedAt: nowProvider(),
            mode: mode,
            fixtureCount: fixtureSet.fixtures.count,
            metrics: averagedMetrics,
            thresholds: rubric.thresholds,
            baseline: baseline?.metrics,
            thresholdFailures: thresholdFailures,
            baselineRegressions: baselineRegressions,
        )
    }

    func makeBaseline(metrics: SummaryBenchmarkMetricSet, source: String) -> SummaryBenchmarkBaseline {
        SummaryBenchmarkBaseline(
            schemaVersion: CanonicalSummary.currentSchemaVersion,
            generatedAt: nowProvider(),
            source: source,
            metrics: metrics,
        )
    }

    private func thresholdFailures(
        metrics: SummaryBenchmarkMetricSet,
        thresholds: SummaryBenchmarkMetricSet,
    ) -> [String] {
        var failures: [String] = []

        if metrics.schemaValidityRate + 1e-9 < thresholds.schemaValidityRate {
            failures.append("schema_validity_rate (\(format(metrics.schemaValidityRate)) < \(format(thresholds.schemaValidityRate)))")
        }
        if metrics.summaryTokenF1 + 1e-9 < thresholds.summaryTokenF1 {
            failures.append("summary_token_f1 (\(format(metrics.summaryTokenF1)) < \(format(thresholds.summaryTokenF1)))")
        }
        if metrics.keyPointsF1 + 1e-9 < thresholds.keyPointsF1 {
            failures.append("key_points_f1 (\(format(metrics.keyPointsF1)) < \(format(thresholds.keyPointsF1)))")
        }
        if metrics.decisionsF1 + 1e-9 < thresholds.decisionsF1 {
            failures.append("decisions_f1 (\(format(metrics.decisionsF1)) < \(format(thresholds.decisionsF1)))")
        }
        if metrics.actionItemsTitleF1 + 1e-9 < thresholds.actionItemsTitleF1 {
            failures.append("action_items_title_f1 (\(format(metrics.actionItemsTitleF1)) < \(format(thresholds.actionItemsTitleF1)))")
        }
        if metrics.openQuestionsF1 + 1e-9 < thresholds.openQuestionsF1 {
            failures.append("open_questions_f1 (\(format(metrics.openQuestionsF1)) < \(format(thresholds.openQuestionsF1)))")
        }
        if metrics.trustFlagsAccuracy + 1e-9 < thresholds.trustFlagsAccuracy {
            failures.append("trust_flags_accuracy (\(format(metrics.trustFlagsAccuracy)) < \(format(thresholds.trustFlagsAccuracy)))")
        }
        if metrics.hallucinationRate - 1e-9 > thresholds.hallucinationRate {
            failures.append("hallucination_rate (\(format(metrics.hallucinationRate)) > \(format(thresholds.hallucinationRate)))")
        }

        return failures
    }

    private func computeBaselineRegressions(
        current: SummaryBenchmarkMetricSet,
        baseline: SummaryBenchmarkMetricSet,
    ) -> [String] {
        var regressions: [String] = []

        if current.schemaValidityRate + 1e-9 < baseline.schemaValidityRate {
            regressions.append("schema_validity_rate regressed (\(format(current.schemaValidityRate)) < \(format(baseline.schemaValidityRate)))")
        }
        if current.summaryTokenF1 + 1e-9 < baseline.summaryTokenF1 {
            regressions.append("summary_token_f1 regressed (\(format(current.summaryTokenF1)) < \(format(baseline.summaryTokenF1)))")
        }
        if current.keyPointsF1 + 1e-9 < baseline.keyPointsF1 {
            regressions.append("key_points_f1 regressed (\(format(current.keyPointsF1)) < \(format(baseline.keyPointsF1)))")
        }
        if current.decisionsF1 + 1e-9 < baseline.decisionsF1 {
            regressions.append("decisions_f1 regressed (\(format(current.decisionsF1)) < \(format(baseline.decisionsF1)))")
        }
        if current.actionItemsTitleF1 + 1e-9 < baseline.actionItemsTitleF1 {
            regressions.append("action_items_title_f1 regressed (\(format(current.actionItemsTitleF1)) < \(format(baseline.actionItemsTitleF1)))")
        }
        if current.openQuestionsF1 + 1e-9 < baseline.openQuestionsF1 {
            regressions.append("open_questions_f1 regressed (\(format(current.openQuestionsF1)) < \(format(baseline.openQuestionsF1)))")
        }
        if current.trustFlagsAccuracy + 1e-9 < baseline.trustFlagsAccuracy {
            regressions.append("trust_flags_accuracy regressed (\(format(current.trustFlagsAccuracy)) < \(format(baseline.trustFlagsAccuracy)))")
        }
        if current.hallucinationRate - 1e-9 > baseline.hallucinationRate {
            regressions.append("hallucination_rate regressed (\(format(current.hallucinationRate)) > \(format(baseline.hallucinationRate)))")
        }

        return regressions
    }

    private func fieldF1(predicted: String?, expected: String) -> Double {
        tokenF1(predictedTokens: tokenize(predicted ?? ""), expectedTokens: tokenize(expected))
    }

    private func parseAndValidateSummary(from providerOutput: String) -> CanonicalSummary? {
        guard let parsed = try? parser.parse(from: providerOutput) else {
            return nil
        }
        guard (try? parsed.validate()) != nil else {
            return nil
        }
        return parsed
    }

    private func trustFlagsAccuracy(predicted: CanonicalSummary?, expected: CanonicalSummary) -> Double {
        guard let predicted else {
            return 0
        }

        var matched = 0.0

        if predicted.trustFlags.isGroundedInTranscript == expected.trustFlags.isGroundedInTranscript {
            matched += 1
        }
        if predicted.trustFlags.containsSpeculation == expected.trustFlags.containsSpeculation {
            matched += 1
        }
        if predicted.trustFlags.isHumanReviewed == expected.trustFlags.isHumanReviewed {
            matched += 1
        }
        if abs(predicted.trustFlags.confidenceScore - expected.trustFlags.confidenceScore) <= 0.05 {
            matched += 1
        }

        return matched / 4
    }

    private func hallucinationRate(transcript: String, predicted: CanonicalSummary?) -> Double {
        guard let predicted else {
            return 1
        }

        let transcriptTokenSet = Set(tokenize(transcript))
        let predictedTokenSet = Set(tokenize(canonicalText(from: predicted)))

        guard !predictedTokenSet.isEmpty else {
            return 0
        }

        let hallucinated = predictedTokenSet.filter { !transcriptTokenSet.contains($0) }
        return Double(hallucinated.count) / Double(predictedTokenSet.count)
    }

    private func canonicalText(from summary: CanonicalSummary) -> String {
        var chunks = [summary.summary]
        chunks.append(summary.keyPoints.joined(separator: " "))
        chunks.append(summary.decisions.joined(separator: " "))
        chunks.append(summary.actionItems.map(\.title).joined(separator: " "))
        chunks.append(summary.openQuestions.joined(separator: " "))
        return chunks.joined(separator: " ")
    }

    private func tokenize(_ text: String) -> [String] {
        text
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private func tokenF1(predictedTokens: [String], expectedTokens: [String]) -> Double {
        if predictedTokens.isEmpty, expectedTokens.isEmpty {
            return 1
        }

        if predictedTokens.isEmpty || expectedTokens.isEmpty {
            return 0
        }

        var expectedBag: [String: Int] = [:]
        for token in expectedTokens {
            expectedBag[token, default: 0] += 1
        }

        var matched = 0
        for token in predictedTokens {
            if let count = expectedBag[token], count > 0 {
                matched += 1
                expectedBag[token] = count - 1
            }
        }

        let precision = Double(matched) / Double(predictedTokens.count)
        let recall = Double(matched) / Double(expectedTokens.count)

        guard precision + recall > 0 else {
            return 0
        }

        return (2 * precision * recall) / (precision + recall)
    }

    private func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

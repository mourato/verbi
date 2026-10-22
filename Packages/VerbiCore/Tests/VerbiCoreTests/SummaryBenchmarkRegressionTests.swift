import Foundation
@testable import VerbiCoreDomain
import XCTest

final class SummaryBenchmarkRegressionTests: XCTestCase {
    private enum EnvironmentKeys {
        static let mode = "MA_SUMMARY_BENCHMARK_MODE"
        static let resultPath = "MA_SUMMARY_BENCHMARK_RESULT_PATH"
        static let baselinePath = "MA_SUMMARY_BENCHMARK_BASELINE_PATH"
        static let recordBaseline = "MA_SUMMARY_BENCHMARK_RECORD_BASELINE"
        static let baselineSource = "MA_SUMMARY_BENCHMARK_BASELINE_SOURCE"
    }

    func testSummaryBenchmarkGate() throws {
        let runner = SummaryBenchmarkRunner()
        let fixtureSet = try runner.loadFixtureSet(from: fixturesURL())

        let modeRaw = ProcessInfo.processInfo.environment[EnvironmentKeys.mode] ?? SummaryBenchmarkGateMode.reportOnly.rawValue
        let mode = SummaryBenchmarkGateMode(rawValue: modeRaw) ?? .reportOnly

        let baseline = try loadBaseline(runner: runner)
        if mode == .enforce {
            XCTAssertNotNil(baseline, "Enforce mode requires a baseline.")
        }

        let result = runner.run(fixtureSet: fixtureSet, mode: mode, baseline: baseline)
        try runner.writeResult(result, to: resultURL())

        if ProcessInfo.processInfo.environment[EnvironmentKeys.recordBaseline] == "1",
           let baselinePath = ProcessInfo.processInfo.environment[EnvironmentKeys.baselinePath],
           !baselinePath.isEmpty
        {
            let source = ProcessInfo.processInfo.environment[EnvironmentKeys.baselineSource] ?? "unspecified-source"
            let baselineToPersist = runner.makeBaseline(metrics: result.metrics, source: source)
            try runner.writeBaseline(baselineToPersist, to: URL(fileURLWithPath: baselinePath))
        }

        XCTAssertGreaterThan(result.fixtureCount, 0)

        if mode == .enforce {
            XCTAssertTrue(
                result.passesEnforcement,
                "Summary benchmark regressions detected. Threshold failures: \(result.thresholdFailures). Baseline regressions: \(result.baselineRegressions).",
            )
        }
    }

    func testFixtureVersionValidationRejectsUnsupportedVersion() throws {
        let tempURL = temporaryURL(named: "summary-benchmark-fixtures-invalid-version.json")
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }
        let payload = """
        {
          "schemaVersion": 3,
          "fixtures": [
            {
              "id": "invalid-version",
              "description": "Invalid schema version fixture",
              "transcript": "A transcript",
              "providerOutput": "{}",
              "expected": {
                "schemaVersion": 2,
                "generatedAt": "2026-02-21T00:00:00Z",
                "title": "A transcript",
                "summary": "A transcript",
                "keyPoints": [],
                "decisions": [],
                "actionItems": [],
                "openQuestions": [],
                "trustFlags": {
                  "isGroundedInTranscript": true,
                  "containsSpeculation": false,
                  "isHumanReviewed": false,
                  "confidenceScore": 1.0
                }
              }
            }
          ]
        }
        """
        try payload.data(using: .utf8)?.write(to: tempURL)

        let runner = SummaryBenchmarkRunner()

        XCTAssertThrowsError(try runner.loadFixtureSet(from: tempURL)) { error in
            XCTAssertEqual(
                error as? SummaryBenchmarkRunnerError,
                .unsupportedFixtureSchemaVersion(3),
            )
        }
    }

    func testSummaryBenchmarkIsDeterministicForSameInput() throws {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let runner = SummaryBenchmarkRunner(nowProvider: { fixedDate })
        let fixtureSet = try runner.loadFixtureSet(from: fixturesURL())
        let baseline = try runner.loadBaseline(from: baselineURL())

        let first = runner.run(fixtureSet: fixtureSet, mode: .enforce, baseline: baseline)
        let second = runner.run(fixtureSet: fixtureSet, mode: .enforce, baseline: baseline)

        XCTAssertEqual(first, second)
    }

    func testThresholdFailuresAreReportedForWeakOutputs() {
        let fixtureSet = SummaryBenchmarkFixtureSet(
            schemaVersion: 2,
            fixtures: [
                SummaryBenchmarkFixture(
                    id: "weak-output",
                    description: "Malformed response should fail quality thresholds",
                    transcript: "Team agreed to ship Friday.",
                    providerOutput: "This is not JSON",
                    expected: CanonicalSummary(
                        generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                        title: "Team agreed to ship Friday",
                        summary: "Team agreed to ship Friday.",
                        keyPoints: ["Ship on Friday"],
                        decisions: ["Release approved"],
                        actionItems: [CanonicalSummary.ActionItem(title: "Prepare release")],
                        openQuestions: [],
                        trustFlags: .init(
                            isGroundedInTranscript: true,
                            containsSpeculation: false,
                            isHumanReviewed: false,
                            confidenceScore: 0.95,
                        ),
                    ),
                ),
            ],
            rubric: .v1,
        )

        let runner = SummaryBenchmarkRunner(nowProvider: { Date(timeIntervalSince1970: 1_700_000_000) })
        let result = runner.run(fixtureSet: fixtureSet, mode: .reportOnly, baseline: nil)

        XCTAssertFalse(result.thresholdFailures.isEmpty)
    }

    func testBaselineRoundTrip() throws {
        let runner = SummaryBenchmarkRunner(nowProvider: { Date(timeIntervalSince1970: 1_700_000_000) })
        let fixtureSet = try runner.loadFixtureSet(from: fixturesURL())
        let result = runner.run(fixtureSet: fixtureSet, mode: .reportOnly, baseline: nil)
        let baseline = runner.makeBaseline(metrics: result.metrics, source: "round-trip-test")

        let tempURL = temporaryURL(named: "summary-benchmark-baseline-roundtrip.json")
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }
        try runner.writeBaseline(baseline, to: tempURL)
        let loadedBaseline = try runner.loadBaseline(from: tempURL)

        XCTAssertEqual(loadedBaseline, baseline)
    }

    func testEnforceModeDetectsBaselineRegression() throws {
        let runner = SummaryBenchmarkRunner(nowProvider: { Date(timeIntervalSince1970: 1_700_000_000) })
        let fixtureSet = try runner.loadFixtureSet(from: fixturesURL())

        let strictBaseline = SummaryBenchmarkBaseline(
            schemaVersion: 1,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            source: "strict-baseline",
            metrics: SummaryBenchmarkMetricSet(
                schemaValidityRate: 1,
                summaryTokenF1: 1.01,
                keyPointsF1: 1,
                decisionsF1: 1,
                actionItemsTitleF1: 1,
                openQuestionsF1: 1,
                trustFlagsAccuracy: 1,
                hallucinationRate: 0,
            ),
        )

        let result = runner.run(fixtureSet: fixtureSet, mode: .enforce, baseline: strictBaseline)
        XCTAssertFalse(result.baselineRegressions.isEmpty)
    }

    private func fixturesURL() throws -> URL {
        try resourceURL(named: "summary-benchmark-fixtures.v1")
    }

    private func baselineURL() throws -> URL {
        try resourceURL(named: "summary-benchmark-baseline.v1")
    }

    private func resourceURL(named resourceName: String) throws -> URL {
        let candidates = [
            Bundle.module.url(forResource: resourceName, withExtension: "json", subdirectory: "Benchmarks"),
            Bundle.module.url(forResource: resourceName, withExtension: "json", subdirectory: "Resources/Benchmarks"),
            Bundle.module.url(forResource: resourceName, withExtension: "json"),
        ]

        guard let url = candidates.compactMap(\.self).first else {
            throw NSError(
                domain: "SummaryBenchmarkRegressionTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing benchmark resource: \(resourceName).json"],
            )
        }

        return url
    }

    private func loadBaseline(runner: SummaryBenchmarkRunner) throws -> SummaryBenchmarkBaseline? {
        if let explicitPath = ProcessInfo.processInfo.environment[EnvironmentKeys.baselinePath], !explicitPath.isEmpty {
            let explicitURL = URL(fileURLWithPath: explicitPath)
            guard FileManager.default.fileExists(atPath: explicitURL.path) else { return nil }
            return try runner.loadBaseline(from: explicitURL)
        }

        return try runner.loadBaseline(from: baselineURL())
    }

    private func resultURL() -> URL {
        if let explicitPath = ProcessInfo.processInfo.environment[EnvironmentKeys.resultPath], !explicitPath.isEmpty {
            return URL(fileURLWithPath: explicitPath)
        }

        return URL(fileURLWithPath: "/tmp/summary-benchmark-result.v1.json")
    }

    private func temporaryURL(named fileName: String) -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName)
    }
}

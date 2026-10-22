@testable import VerbiCore
import XCTest

final class ModelPerformanceAggregatorTests: XCTestCase {
    func testComputeAnalysis_KeepsProviderModelBucketsSeparate() {
        let attempts = [
            makeAttempt(providerID: "local", providerName: "Local", modelID: "whisper-large"),
            makeAttempt(providerID: "groq", providerName: "Groq", modelID: "whisper-large"),
        ]

        let analysis = ModelPerformanceAggregator.computeAnalysis(
            attempts: attempts,
            stage: .transcription,
        )

        XCTAssertEqual(analysis.summary.distinctModels, 2)
        XCTAssertEqual(analysis.leaderboard.count, 2)
        XCTAssertEqual(Set(analysis.leaderboard.map(\.identity.providerID)), ["local", "groq"])
    }

    func testComputeAnalysis_PostProcessingThroughputUsesBytesPerSecond() throws {
        let attempts = [
            makeAttempt(
                stage: .postProcessing,
                providerID: "openai",
                providerName: "OpenAI",
                modelID: "gpt-4.1-mini",
                wallClockSeconds: 2,
                audioSeconds: 600,
                inputUTF8Bytes: 4_000,
                inputCharacterCount: 1_000,
            ),
        ]

        let analysis = ModelPerformanceAggregator.computeAnalysis(
            attempts: attempts,
            stage: .postProcessing,
        )

        let entry = try XCTUnwrap(analysis.leaderboard.first)
        XCTAssertEqual(entry.normalizedThroughput, 2_000, accuracy: 0.001)
        XCTAssertEqual(entry.secondaryThroughput, 500, accuracy: 0.001)
    }

    func testComputeAnalysis_RanksHigherSuccessRateAheadOfFasterModel() throws {
        let reliableAttempts = [
            makeAttempt(providerID: "local", providerName: "Local", modelID: "fast-a", wallClockSeconds: 12),
            makeAttempt(providerID: "local", providerName: "Local", modelID: "fast-a", wallClockSeconds: 10),
            makeAttempt(providerID: "local", providerName: "Local", modelID: "fast-a", wallClockSeconds: 11),
        ]
        let flakyAttempts = [
            makeAttempt(providerID: "groq", providerName: "Groq", modelID: "fast-b", wallClockSeconds: 4),
            makeAttempt(providerID: "groq", providerName: "Groq", modelID: "fast-b", wallClockSeconds: 5),
            makeAttempt(providerID: "groq", providerName: "Groq", modelID: "fast-b", status: .failed, wallClockSeconds: 3),
            makeAttempt(providerID: "groq", providerName: "Groq", modelID: "fast-b", status: .failed, wallClockSeconds: 3),
        ]

        let analysis = ModelPerformanceAggregator.computeAnalysis(
            attempts: reliableAttempts + flakyAttempts,
            stage: .transcription,
        )

        let first = try XCTUnwrap(analysis.leaderboard.first)
        let last = try XCTUnwrap(analysis.leaderboard.last)
        XCTAssertEqual(first.identity.providerID, "local")
        XCTAssertEqual(first.successRate, 1.0, accuracy: 0.001)
        XCTAssertEqual(last.identity.providerID, "groq")
    }

    func testComputeAnalysis_BestBalanceBadgeRequiresAtLeastThreeAttempts() throws {
        let lowSample = [
            makeAttempt(providerID: "local", providerName: "Local", modelID: "model-a", wallClockSeconds: 4),
            makeAttempt(providerID: "local", providerName: "Local", modelID: "model-a", wallClockSeconds: 5),
        ]
        let sufficientSample = [
            makeAttempt(providerID: "openai", providerName: "OpenAI", modelID: "model-b", wallClockSeconds: 8),
            makeAttempt(providerID: "openai", providerName: "OpenAI", modelID: "model-b", wallClockSeconds: 8),
            makeAttempt(providerID: "openai", providerName: "OpenAI", modelID: "model-b", wallClockSeconds: 9),
        ]

        let analysis = ModelPerformanceAggregator.computeAnalysis(
            attempts: lowSample + sufficientSample,
            stage: .transcription,
        )

        let lowSampleEntry = try XCTUnwrap(analysis.leaderboard.first { $0.identity.modelID == "model-a" })
        let sufficientSampleEntry = try XCTUnwrap(analysis.leaderboard.first { $0.identity.modelID == "model-b" })

        XCTAssertFalse(lowSampleEntry.isBestBalance)
        XCTAssertTrue(sufficientSampleEntry.isBestBalance)
    }

    private func makeAttempt(
        stage: ModelPerformanceStage = .transcription,
        providerID: String,
        providerName: String,
        modelID: String,
        status: ModelPerformanceAttemptStatus = .succeeded,
        wallClockSeconds: Double = 10,
        audioSeconds: Double = 60,
        inputUTF8Bytes: Int = 0,
        inputCharacterCount: Int = 0,
    ) -> ModelPerformanceAttempt {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return ModelPerformanceAttempt(
            transcriptionID: UUID(),
            stage: stage,
            attemptKind: .initial,
            capturePurpose: .meeting,
            modelIdentity: ModelPerformanceModelIdentity(
                providerID: providerID,
                providerDisplayName: providerName,
                modelID: modelID,
                modelDisplayName: modelID,
                runtimeKind: .remote,
            ),
            status: status,
            startedAt: now,
            completedAt: now.addingTimeInterval(wallClockSeconds),
            wallClockSeconds: wallClockSeconds,
            audioSeconds: audioSeconds,
            inputUTF8Bytes: inputUTF8Bytes,
            inputCharacterCount: inputCharacterCount,
            outputCharacterCount: 100,
            failureReason: status == .failed ? "failed" : nil,
        )
    }
}

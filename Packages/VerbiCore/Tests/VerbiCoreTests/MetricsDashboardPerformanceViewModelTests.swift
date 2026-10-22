@testable import VerbiCore
@testable import VerbiCoreUI
import XCTest

@MainActor
final class PerformanceViewModelTests: XCTestCase {
    func testLoad_BuildsProviderOptionsAndOrdersHistoryNewestFirst() async {
        let storage = MockStorageService()
        let older = makeAttempt(
            providerID: "local",
            providerName: "Local",
            modelID: "whisper-a",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
        let newer = makeAttempt(
            providerID: "groq",
            providerName: "Groq",
            modelID: "whisper-b",
            startedAt: Date(timeIntervalSince1970: 1_700_000_100),
        )
        storage.savedModelPerformanceAttempts = [older, newer]

        let viewModel = MetricsDashboardPerformanceViewModel(storage: storage)
        await viewModel.load()

        XCTAssertEqual(viewModel.providerOptions.map(\.id), ["groq", "local"])
        XCTAssertEqual(viewModel.history.map(\.id), [newer.id, older.id])
        XCTAssertEqual(viewModel.analysis.summary.totalAttempts, 2)
    }

    func testLoad_AppliesProviderFilterToAnalysis() async {
        let storage = MockStorageService()
        storage.savedModelPerformanceAttempts = [
            makeAttempt(providerID: "local", providerName: "Local", modelID: "whisper-a"),
            makeAttempt(providerID: "groq", providerName: "Groq", modelID: "whisper-b"),
        ]

        let viewModel = MetricsDashboardPerformanceViewModel(storage: storage)
        await viewModel.load()
        viewModel.providerID = "local"

        XCTAssertEqual(viewModel.analysis.summary.totalAttempts, 1)
        XCTAssertEqual(viewModel.history.first?.modelIdentity.providerID, "local")
        XCTAssertEqual(viewModel.providerOptions.count, 2)
    }

    func testLoad_StatusFilterRefreshesResults() async {
        let storage = MockStorageService()
        storage.savedModelPerformanceAttempts = [
            makeAttempt(providerID: "local", providerName: "Local", modelID: "whisper-a", status: .succeeded),
            makeAttempt(providerID: "groq", providerName: "Groq", modelID: "whisper-b", status: .failed),
        ]

        let viewModel = MetricsDashboardPerformanceViewModel(storage: storage)
        await viewModel.load()

        viewModel.statusFilter = ModelPerformanceStatusFilter.failed
        await viewModel.load()

        XCTAssertEqual(viewModel.analysis.summary.totalAttempts, 1)
        XCTAssertEqual(viewModel.history.first?.status, .failed)
        XCTAssertEqual(viewModel.history.first?.modelIdentity.modelID, "whisper-b")
    }

    func testHistory_ReturnsOnlyTenMostRecentAttempts() async {
        let storage = MockStorageService()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        storage.savedModelPerformanceAttempts = (0..<12).map { index in
            makeAttempt(
                providerID: "local",
                providerName: "Local",
                modelID: "whisper-\(index)",
                startedAt: baseDate.addingTimeInterval(Double(index)),
            )
        }

        let viewModel = MetricsDashboardPerformanceViewModel(storage: storage)
        await viewModel.load()

        XCTAssertEqual(viewModel.history.count, 10)
        XCTAssertEqual(viewModel.history.first?.modelIdentity.modelID, "whisper-11")
        XCTAssertEqual(viewModel.history.last?.modelIdentity.modelID, "whisper-2")
    }

    private func makeAttempt(
        providerID: String,
        providerName: String,
        modelID: String,
        status: ModelPerformanceAttemptStatus = .succeeded,
        startedAt: Date = Date(),
    ) -> ModelPerformanceAttempt {
        ModelPerformanceAttempt(
            transcriptionID: UUID(),
            stage: .transcription,
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
            startedAt: startedAt,
            completedAt: startedAt.addingTimeInterval(10),
            wallClockSeconds: 10,
            audioSeconds: 90,
            inputUTF8Bytes: 0,
            inputCharacterCount: 0,
            outputCharacterCount: 100,
            failureReason: status == .failed ? "failed" : nil,
        )
    }
}

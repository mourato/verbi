import Foundation
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain

@MainActor
final class MetricsDashboardPerformanceViewModel: ObservableObject {
    struct ProviderOption: Identifiable, Equatable {
        let id: String
        let displayName: String
    }

    @Published var stage: ModelPerformanceStage = .transcription {
        didSet {
            guard oldValue != stage else { return }
            providerID = nil
            reload()
        }
    }

    @Published var captureFilter: PerformanceFilter = .all {
        didSet {
            guard oldValue != captureFilter else { return }
            reload()
        }
    }

    @Published var dateFilter: DateFilter = .allEntries {
        didSet {
            guard oldValue != dateFilter else { return }
            reload()
        }
    }

    @Published var statusFilter: ModelPerformanceStatusFilter = .all {
        didSet {
            guard oldValue != statusFilter else { return }
            reload()
        }
    }

    @Published var providerID: String? {
        didSet {
            guard oldValue != providerID else { return }
            recomputeAnalysis()
        }
    }

    @Published var leaderboardSort: LeaderboardSort = .bestBalance

    @Published private(set) var analysis = ModelPerformanceAnalysis.empty(for: .transcription)
    @Published private(set) var providerOptions: [ProviderOption] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let storage: StorageService
    private var cachedAttempts: [ModelPerformanceAttempt] = []
    private var loadTask: Task<Void, Never>?

    init(storage: StorageService = FileSystemStorageService.shared) {
        self.storage = storage
    }

    deinit {
        loadTask?.cancel()
    }

    var sortedLeaderboard: [ModelPerformanceLeaderboardEntry] {
        analysis.sortedByLeaderboard(leaderboardSort)
    }

    var history: [ModelPerformanceAttempt] {
        Array(analysis.history.prefix(10))
    }

    func load() async {
        await refresh()
    }

    func reload() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.refresh()
        }
    }

    private func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let attempts = try await storage.loadModelPerformanceAttempts(matching: baseQuery)
            try Task.checkCancellation()
            cachedAttempts = attempts.sorted { $0.startedAt > $1.startedAt }
            providerOptions = Self.makeProviderOptions(from: cachedAttempts)
            if let providerID, !providerOptions.contains(where: { $0.id == providerID }) {
                self.providerID = nil
            } else {
                recomputeAnalysis()
            }
        } catch is CancellationError {
            return
        } catch {
            cachedAttempts = []
            providerOptions = []
            analysis = .empty(for: stage)
            errorMessage = "metrics.error.load".localized
        }
    }

    private var baseQuery: ModelPerformanceAttemptQuery {
        ModelPerformanceAttemptQuery(
            stage: stage,
            captureFilter: captureFilter,
            dateFilter: dateFilter,
            providerID: nil,
            statusFilter: statusFilter,
            modelSearchText: "",
            limit: nil
        )
    }

    private func recomputeAnalysis() {
        let filteredAttempts: [ModelPerformanceAttempt] = if let providerID, !providerID.isEmpty {
            cachedAttempts.filter { $0.modelIdentity.providerID == providerID }
        } else {
            cachedAttempts
        }
        analysis = ModelPerformanceAggregator.computeAnalysis(
            attempts: filteredAttempts,
            stage: stage
        )
    }

    private static func makeProviderOptions(from attempts: [ModelPerformanceAttempt]) -> [ProviderOption] {
        Dictionary(grouping: attempts, by: { $0.modelIdentity.providerID })
            .compactMap { providerID, values in
                guard let displayName = values.first?.modelIdentity.providerDisplayName else { return nil }
                return ProviderOption(id: providerID, displayName: displayName)
            }
            .sorted { lhs, rhs in
                lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }
}

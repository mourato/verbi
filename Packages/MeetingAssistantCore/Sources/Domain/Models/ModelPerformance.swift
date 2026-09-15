import Foundation
import MeetingAssistantCoreCommon

public enum ModelPerformanceStage: String, Codable, CaseIterable, Sendable {
    case transcription
    case postProcessing

    public var displayName: String {
        switch self {
        case .transcription:
            "metrics.performance.stage.transcription".localized
        case .postProcessing:
            "metrics.performance.stage.post_processing".localized
        }
    }
}

public enum ModelPerformanceAttemptKind: String, Codable, Sendable {
    case initial
    case retry
    case reprocess

    public var displayName: String {
        switch self {
        case .initial:
            "metrics.performance.attempt_kind.initial".localized
        case .retry:
            "metrics.performance.attempt_kind.retry".localized
        case .reprocess:
            "metrics.performance.attempt_kind.reprocess".localized
        }
    }
}

public enum ModelPerformanceAttemptStatus: String, Codable, CaseIterable, Sendable {
    case succeeded
    case failed

    public var displayName: String {
        switch self {
        case .succeeded:
            "metrics.performance.status.succeeded".localized
        case .failed:
            "metrics.performance.status.failed".localized
        }
    }
}

public enum ModelPerformanceRuntimeKind: String, Codable, CaseIterable, Sendable {
    case local
    case remote
    case xpc
    case unknown

    public var displayName: String {
        switch self {
        case .local:
            "metrics.performance.runtime.local".localized
        case .remote:
            "metrics.performance.runtime.remote".localized
        case .xpc:
            "metrics.performance.runtime.xpc".localized
        case .unknown:
            "metrics.performance.runtime.unknown".localized
        }
    }
}

public struct ModelPerformanceModelIdentity: Codable, Hashable, Sendable {
    public let providerID: String
    public let providerDisplayName: String
    public let modelID: String
    public let modelDisplayName: String
    public let runtimeKind: ModelPerformanceRuntimeKind

    public init(
        providerID: String,
        providerDisplayName: String,
        modelID: String,
        modelDisplayName: String,
        runtimeKind: ModelPerformanceRuntimeKind
    ) {
        self.providerID = providerID
        self.providerDisplayName = providerDisplayName
        self.modelID = modelID
        self.modelDisplayName = modelDisplayName
        self.runtimeKind = runtimeKind
    }

    public var aggregateKey: String {
        "\(providerID)::\(modelID)"
    }
}

public struct ModelPerformanceAttempt: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let transcriptionID: UUID
    public let stage: ModelPerformanceStage
    public let attemptKind: ModelPerformanceAttemptKind
    public let capturePurpose: CapturePurpose
    public let modelIdentity: ModelPerformanceModelIdentity
    public let status: ModelPerformanceAttemptStatus
    public let startedAt: Date
    public let completedAt: Date
    public let wallClockSeconds: Double
    public let audioSeconds: Double
    public let inputUTF8Bytes: Int
    public let inputCharacterCount: Int
    public let outputCharacterCount: Int
    public let failureReason: String?
    public let executionProvenance: ExecutionProvenance?

    public init(
        id: UUID = UUID(),
        transcriptionID: UUID,
        stage: ModelPerformanceStage,
        attemptKind: ModelPerformanceAttemptKind,
        capturePurpose: CapturePurpose,
        modelIdentity: ModelPerformanceModelIdentity,
        status: ModelPerformanceAttemptStatus,
        startedAt: Date,
        completedAt: Date,
        wallClockSeconds: Double,
        audioSeconds: Double,
        inputUTF8Bytes: Int,
        inputCharacterCount: Int,
        outputCharacterCount: Int,
        failureReason: String? = nil,
        executionProvenance: ExecutionProvenance? = nil
    ) {
        self.id = id
        self.transcriptionID = transcriptionID
        self.stage = stage
        self.attemptKind = attemptKind
        self.capturePurpose = capturePurpose
        self.modelIdentity = modelIdentity
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.wallClockSeconds = wallClockSeconds
        self.audioSeconds = audioSeconds
        self.inputUTF8Bytes = inputUTF8Bytes
        self.inputCharacterCount = inputCharacterCount
        self.outputCharacterCount = outputCharacterCount
        self.failureReason = failureReason
        self.executionProvenance = executionProvenance
    }
}

public struct ModelPerformanceAttemptQuery: Hashable, Sendable {
    public let stage: ModelPerformanceStage
    public let captureFilter: PerformanceFilter
    public let dateFilter: DateFilter
    public let providerID: String?
    public let statusFilter: ModelPerformanceStatusFilter
    public let modelSearchText: String
    public let limit: Int?

    public init(
        stage: ModelPerformanceStage = .transcription,
        captureFilter: PerformanceFilter = .all,
        dateFilter: DateFilter = .allEntries,
        providerID: String? = nil,
        statusFilter: ModelPerformanceStatusFilter = .all,
        modelSearchText: String = "",
        limit: Int? = nil
    ) {
        self.stage = stage
        self.captureFilter = captureFilter
        self.dateFilter = dateFilter
        self.providerID = providerID
        self.statusFilter = statusFilter
        self.modelSearchText = modelSearchText
        self.limit = limit
    }
}

public enum ModelPerformanceStatusFilter: String, CaseIterable, Sendable {
    case all
    case succeeded
    case failed

    public var displayName: String {
        switch self {
        case .all:
            "metrics.performance.status_filter.all".localized
        case .succeeded:
            ModelPerformanceAttemptStatus.succeeded.displayName
        case .failed:
            ModelPerformanceAttemptStatus.failed.displayName
        }
    }
}

public struct ModelPerformanceSummary: Equatable, Sendable {
    public let stage: ModelPerformanceStage
    public let totalAttempts: Int
    public let successfulAttempts: Int
    public let failedAttempts: Int
    public let distinctModels: Int
    public let fastestModelDisplayName: String?
    public let fastestModelThroughput: Double

    public init(
        stage: ModelPerformanceStage,
        totalAttempts: Int,
        successfulAttempts: Int,
        failedAttempts: Int,
        distinctModels: Int,
        fastestModelDisplayName: String?,
        fastestModelThroughput: Double
    ) {
        self.stage = stage
        self.totalAttempts = totalAttempts
        self.successfulAttempts = successfulAttempts
        self.failedAttempts = failedAttempts
        self.distinctModels = distinctModels
        self.fastestModelDisplayName = fastestModelDisplayName
        self.fastestModelThroughput = fastestModelThroughput
    }

    public static func empty(for stage: ModelPerformanceStage) -> ModelPerformanceSummary {
        ModelPerformanceSummary(
            stage: stage,
            totalAttempts: 0,
            successfulAttempts: 0,
            failedAttempts: 0,
            distinctModels: 0,
            fastestModelDisplayName: nil,
            fastestModelThroughput: 0
        )
    }
}

public struct ModelPerformanceLeaderboardEntry: Identifiable, Equatable, Sendable {
    public let identity: ModelPerformanceModelIdentity
    public let attemptCount: Int
    public let successfulAttempts: Int
    public let failedAttempts: Int
    public let successRate: Double
    public let medianWallClockSeconds: Double
    public let averageWallClockSeconds: Double
    public let normalizedThroughput: Double
    public let secondaryThroughput: Double
    public let isBestBalance: Bool

    public init(
        identity: ModelPerformanceModelIdentity,
        attemptCount: Int,
        successfulAttempts: Int,
        failedAttempts: Int,
        successRate: Double,
        medianWallClockSeconds: Double,
        averageWallClockSeconds: Double,
        normalizedThroughput: Double,
        secondaryThroughput: Double,
        isBestBalance: Bool
    ) {
        self.identity = identity
        self.attemptCount = attemptCount
        self.successfulAttempts = successfulAttempts
        self.failedAttempts = failedAttempts
        self.successRate = successRate
        self.medianWallClockSeconds = medianWallClockSeconds
        self.averageWallClockSeconds = averageWallClockSeconds
        self.normalizedThroughput = normalizedThroughput
        self.secondaryThroughput = secondaryThroughput
        self.isBestBalance = isBestBalance
    }

    public var id: String {
        identity.aggregateKey
    }
}

public struct ModelPerformanceAnalysis: Equatable, Sendable {
    public let stage: ModelPerformanceStage
    public let summary: ModelPerformanceSummary
    public let leaderboard: [ModelPerformanceLeaderboardEntry]
    public let history: [ModelPerformanceAttempt]
    public let availableProviderIDs: [String]

    public init(
        stage: ModelPerformanceStage,
        summary: ModelPerformanceSummary,
        leaderboard: [ModelPerformanceLeaderboardEntry],
        history: [ModelPerformanceAttempt],
        availableProviderIDs: [String]
    ) {
        self.stage = stage
        self.summary = summary
        self.leaderboard = leaderboard
        self.history = history
        self.availableProviderIDs = availableProviderIDs
    }

    public static func empty(for stage: ModelPerformanceStage) -> ModelPerformanceAnalysis {
        ModelPerformanceAnalysis(
            stage: stage,
            summary: .empty(for: stage),
            leaderboard: [],
            history: [],
            availableProviderIDs: []
        )
    }
}

public enum PerformanceFilter: String, CaseIterable, Sendable {
    case all
    case dictation
    case meeting

    public var displayName: String {
        switch self {
        case .all:
            "metrics.performance.filter.all".localized
        case .dictation:
            "metrics.performance.filter.dictation".localized
        case .meeting:
            "metrics.performance.filter.meeting".localized
        }
    }
}

public enum LeaderboardSort: String, CaseIterable, Sendable {
    case bestBalance
    case successRate
    case throughput
    case medianLatency
    case attempts

    public var displayName: String {
        switch self {
        case .bestBalance:
            "metrics.performance.sort.best_balance".localized
        case .successRate:
            "metrics.performance.sort.success_rate".localized
        case .throughput:
            "metrics.performance.sort.throughput".localized
        case .medianLatency:
            "metrics.performance.sort.median_latency".localized
        case .attempts:
            "metrics.performance.sort.attempts".localized
        }
    }
}

public extension ModelPerformanceAnalysis {
    func sortedByLeaderboard(_ sort: LeaderboardSort) -> [ModelPerformanceLeaderboardEntry] {
        switch sort {
        case .bestBalance:
            leaderboard.sorted { lhs, rhs in
                if lhs.isBestBalance != rhs.isBestBalance {
                    lhs.isBestBalance && !rhs.isBestBalance
                } else if lhs.successRate != rhs.successRate {
                    lhs.successRate > rhs.successRate
                } else if lhs.normalizedThroughput != rhs.normalizedThroughput {
                    lhs.normalizedThroughput > rhs.normalizedThroughput
                } else {
                    lhs.medianWallClockSeconds < rhs.medianWallClockSeconds
                }
            }
        case .successRate:
            leaderboard.sorted { lhs, rhs in
                if lhs.successRate != rhs.successRate {
                    lhs.successRate > rhs.successRate
                } else {
                    lhs.attemptCount > rhs.attemptCount
                }
            }
        case .throughput:
            leaderboard.sorted { lhs, rhs in
                if lhs.normalizedThroughput != rhs.normalizedThroughput {
                    lhs.normalizedThroughput > rhs.normalizedThroughput
                } else {
                    lhs.successRate > rhs.successRate
                }
            }
        case .medianLatency:
            leaderboard.sorted { lhs, rhs in
                if lhs.medianWallClockSeconds != rhs.medianWallClockSeconds {
                    lhs.medianWallClockSeconds < rhs.medianWallClockSeconds
                } else {
                    lhs.successRate > rhs.successRate
                }
            }
        case .attempts:
            leaderboard.sorted { lhs, rhs in
                if lhs.attemptCount != rhs.attemptCount {
                    lhs.attemptCount > rhs.attemptCount
                } else {
                    lhs.successRate > rhs.successRate
                }
            }
        }
    }
}

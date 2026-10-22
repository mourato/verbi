import Foundation

/// Canonical and versioned summary payload persisted with a transcription.
public struct CanonicalSummary: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let generatedAt: Date
    public let title: String
    public let summary: String
    public let keyPoints: [String]
    public let decisions: [String]
    public let actionItems: [ActionItem]
    public let openQuestions: [String]
    public let trustFlags: TrustFlags

    public init(
        schemaVersion: Int = CanonicalSummary.currentSchemaVersion,
        generatedAt: Date = Date(),
        title: String,
        summary: String,
        keyPoints: [String] = [],
        decisions: [String] = [],
        actionItems: [ActionItem] = [],
        openQuestions: [String] = [],
        trustFlags: TrustFlags = .init()
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.title = title
        self.summary = summary
        self.keyPoints = keyPoints
        self.decisions = decisions
        self.actionItems = actionItems
        self.openQuestions = openQuestions
        self.trustFlags = trustFlags
    }

    public func validate() throws {
        guard schemaVersion > 0, schemaVersion <= Self.currentSchemaVersion else {
            throw CanonicalSummaryValidationError.unsupportedSchemaVersion(schemaVersion)
        }

        guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CanonicalSummaryValidationError.emptySummary
        }

        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CanonicalSummaryValidationError.emptyTitle
        }

        try validateListEntries(keyPoints, fieldName: "keyPoints")
        try validateListEntries(decisions, fieldName: "decisions")
        try validateListEntries(openQuestions, fieldName: "openQuestions")

        for item in actionItems where item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw CanonicalSummaryValidationError.emptyActionItemTitle
        }

        guard (0.0 ... 1.0).contains(trustFlags.confidenceScore) else {
            throw CanonicalSummaryValidationError.invalidConfidenceScore(trustFlags.confidenceScore)
        }
    }

    private func validateListEntries(_ values: [String], fieldName: String) throws {
        if values.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            throw CanonicalSummaryValidationError.emptyListEntry(fieldName)
        }
    }
}

public extension CanonicalSummary {
    struct ActionItem: Codable, Hashable, Sendable {
        public let title: String
        public let owner: String?
        public let dueDate: Date?

        public init(title: String, owner: String? = nil, dueDate: Date? = nil) {
            self.title = title
            self.owner = owner
            self.dueDate = dueDate
        }
    }

    struct TrustFlags: Codable, Hashable, Sendable {
        public let isGroundedInTranscript: Bool
        public let containsSpeculation: Bool
        public let isHumanReviewed: Bool
        public let confidenceScore: Double

        public init(
            isGroundedInTranscript: Bool = false,
            containsSpeculation: Bool = false,
            isHumanReviewed: Bool = false,
            confidenceScore: Double = 0.0
        ) {
            self.isGroundedInTranscript = isGroundedInTranscript
            self.containsSpeculation = containsSpeculation
            self.isHumanReviewed = isHumanReviewed
            self.confidenceScore = confidenceScore
        }
    }
}

public enum CanonicalSummaryValidationError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedSchemaVersion(Int)
    case emptyTitle
    case emptySummary
    case emptyListEntry(String)
    case emptyActionItemTitle
    case invalidConfidenceScore(Double)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchemaVersion(version):
            "Unsupported canonical summary schema version: \(version)"
        case .emptyTitle:
            "Canonical summary title must not be empty."
        case .emptySummary:
            "Canonical summary must not be empty."
        case let .emptyListEntry(field):
            "Canonical summary field '\(field)' contains empty entries."
        case .emptyActionItemTitle:
            "Canonical summary action items must have a non-empty title."
        case let .invalidConfidenceScore(score):
            "Canonical summary confidence score must be between 0 and 1. Received: \(score)"
        }
    }
}

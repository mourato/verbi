import Foundation

public enum SummaryExportSafetyPolicyLevel: String, CaseIterable, Codable, Sendable {
    case permissive
    case standard
    case strict

    public var minimumConfidenceScore: Double {
        switch self {
        case .permissive:
            0.35
        case .standard:
            0.60
        case .strict:
            0.80
        }
    }

    public var appliesSensitiveRedaction: Bool {
        switch self {
        case .permissive:
            false
        case .standard, .strict:
            true
        }
    }
}

public struct SummaryExportBlockReason: Codable, Hashable, Sendable {
    public enum Code: String, Codable, Sendable {
        case missingExportFolder
        case emptyExportContent
        case missingCanonicalSummary
        case invalidCanonicalSummary
        case notGroundedInTranscript
        case confidenceBelowThreshold
    }

    public let code: Code
    public let message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }
}

public struct SummaryExportSafetyDecision: Codable, Hashable, Sendable {
    public let policyLevel: SummaryExportSafetyPolicyLevel
    public let blockReasons: [SummaryExportBlockReason]
    public let requiredMinimumConfidence: Double
    public let observedConfidence: Double?

    public init(
        policyLevel: SummaryExportSafetyPolicyLevel,
        blockReasons: [SummaryExportBlockReason],
        requiredMinimumConfidence: Double,
        observedConfidence: Double?
    ) {
        self.policyLevel = policyLevel
        self.blockReasons = blockReasons
        self.requiredMinimumConfidence = requiredMinimumConfidence
        self.observedConfidence = observedConfidence
    }

    public var isCompliant: Bool {
        blockReasons.isEmpty
    }
}

import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain

public struct SummaryExportSafetyEvaluator: Sendable {
    public init() {}

    public func evaluate(
        transcription: Transcription,
        exportDestination: URL?,
        candidateContent: String,
        policyLevel: SummaryExportSafetyPolicyLevel
    ) -> SummaryExportSafetyDecision {
        var reasons: [SummaryExportBlockReason] = []

        if exportDestination == nil {
            reasons.append(.init(
                code: .missingExportFolder,
                message: "Export folder is not configured."
            ))
        }

        if candidateContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reasons.append(.init(
                code: .emptyExportContent,
                message: "Export content is empty."
            ))
        }

        var observedConfidence: Double?

        guard let canonicalSummary = transcription.canonicalSummary else {
            reasons.append(.init(
                code: .missingCanonicalSummary,
                message: "Canonical summary is required for safe export."
            ))

            return SummaryExportSafetyDecision(
                policyLevel: policyLevel,
                blockReasons: reasons,
                requiredMinimumConfidence: policyLevel.minimumConfidenceScore,
                observedConfidence: observedConfidence
            )
        }

        do {
            try canonicalSummary.validate()
        } catch {
            reasons.append(.init(
                code: .invalidCanonicalSummary,
                message: "Canonical summary payload is invalid."
            ))
        }

        if !canonicalSummary.trustFlags.isGroundedInTranscript {
            reasons.append(.init(
                code: .notGroundedInTranscript,
                message: "Canonical summary is not grounded in the transcript."
            ))
        }

        observedConfidence = canonicalSummary.trustFlags.confidenceScore
        if canonicalSummary.trustFlags.confidenceScore + 1e-9 < policyLevel.minimumConfidenceScore {
            reasons.append(.init(
                code: .confidenceBelowThreshold,
                message: "Confidence score \(canonicalSummary.trustFlags.confidenceScore) is below required threshold \(policyLevel.minimumConfidenceScore)."
            ))
        }

        return SummaryExportSafetyDecision(
            policyLevel: policyLevel,
            blockReasons: reasons,
            requiredMinimumConfidence: policyLevel.minimumConfidenceScore,
            observedConfidence: observedConfidence
        )
    }

    public func applyRedactionIfNeeded(
        to value: String,
        policyLevel: SummaryExportSafetyPolicyLevel
    ) -> String {
        guard policyLevel.appliesSensitiveRedaction else {
            return value
        }

        return ContextAwarenessPrivacy.redactSensitiveText(value) ?? value
    }
}

public enum SummaryExportAuditOutcome: String, Codable, Sendable {
    case blocked
    case exported
    case writeFailed = "write_failed"
}

public struct SummaryExportAuditEvent: Codable, Sendable {
    public let timestamp: Date
    public let transcriptionID: UUID
    public let meetingID: UUID
    public let outcome: SummaryExportAuditOutcome
    public let policyLevel: SummaryExportSafetyPolicyLevel
    public let blockReasonCodes: [SummaryExportBlockReason.Code]
    public let blockReasonMessages: [String]
    public let requiredMinimumConfidence: Double
    public let observedConfidence: Double?
    public let canonicalSummaryPresent: Bool
    public let groundedInTranscript: Bool?
    public let redactionApplied: Bool
    public let destinationPath: String?
    public let errorDescription: String?

    public init(
        timestamp: Date,
        transcriptionID: UUID,
        meetingID: UUID,
        outcome: SummaryExportAuditOutcome,
        policyLevel: SummaryExportSafetyPolicyLevel,
        blockReasonCodes: [SummaryExportBlockReason.Code],
        blockReasonMessages: [String],
        requiredMinimumConfidence: Double,
        observedConfidence: Double?,
        canonicalSummaryPresent: Bool,
        groundedInTranscript: Bool?,
        redactionApplied: Bool,
        destinationPath: String?,
        errorDescription: String?
    ) {
        self.timestamp = timestamp
        self.transcriptionID = transcriptionID
        self.meetingID = meetingID
        self.outcome = outcome
        self.policyLevel = policyLevel
        self.blockReasonCodes = blockReasonCodes
        self.blockReasonMessages = blockReasonMessages
        self.requiredMinimumConfidence = requiredMinimumConfidence
        self.observedConfidence = observedConfidence
        self.canonicalSummaryPresent = canonicalSummaryPresent
        self.groundedInTranscript = groundedInTranscript
        self.redactionApplied = redactionApplied
        self.destinationPath = destinationPath
        self.errorDescription = errorDescription
    }
}

public struct SummaryExportAuditTrailWriter {
    private let fileManager: FileManager
    private let nowProvider: @Sendable () -> Date
    private let rootDirectoryURL: URL?

    public init(
        fileManager: FileManager = .default,
        nowProvider: @escaping @Sendable () -> Date = Date.init,
        rootDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.nowProvider = nowProvider
        self.rootDirectoryURL = rootDirectoryURL
    }

    public func append(_ event: SummaryExportAuditEvent) throws {
        let auditFileURL = try resolveAuditFileURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601

        let payload = try encoder.encode(event)
        guard let line = String(data: payload, encoding: .utf8) else {
            throw NSError(domain: "SummaryExportAuditTrailWriter", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to encode export audit line."
            ])
        }

        let fileLine = line + "\n"
        if !fileManager.fileExists(atPath: auditFileURL.path) {
            try fileLine.write(to: auditFileURL, atomically: true, encoding: .utf8)
            return
        }

        let handle = try FileHandle(forWritingTo: auditFileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        if let data = fileLine.data(using: .utf8) {
            try handle.write(contentsOf: data)
        }
    }

    private func resolveAuditFileURL() throws -> URL {
        let rootURL: URL
        if let rootDirectoryURL {
            rootURL = rootDirectoryURL
        } else {
            let logsURL = AppIdentity.logsBaseDirectory(fileManager: fileManager)
            rootURL = logsURL.appendingPathComponent("ExportAudit", isDirectory: true)
        }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let dateStamp = DateFormatter.auditDayStamp.string(from: nowProvider())
        return rootURL.appendingPathComponent("export-audit-\(dateStamp).jsonl")
    }
}

private extension DateFormatter {
    static let auditDayStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

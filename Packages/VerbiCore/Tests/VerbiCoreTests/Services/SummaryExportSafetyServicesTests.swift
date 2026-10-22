import Foundation
@testable import VerbiCore
import XCTest

final class SummaryExportSafetyServicesTests: XCTestCase {
    func testEvaluateBlocksWhenCanonicalSummaryIsMissing() {
        let evaluator = SummaryExportSafetyEvaluator()
        let transcription = makeTranscription(canonicalSummary: nil)

        let decision = evaluator.evaluate(
            transcription: transcription,
            exportDestination: URL(fileURLWithPath: "/tmp"),
            candidateContent: "Valid content",
            policyLevel: .standard,
        )

        XCTAssertFalse(decision.isCompliant)
        XCTAssertTrue(decision.blockReasons.contains(where: { $0.code == .missingCanonicalSummary }))
    }

    func testEvaluateBlocksWhenNotGroundedOrConfidenceTooLow() {
        let evaluator = SummaryExportSafetyEvaluator()
        let summary = CanonicalSummary(
            title: "Summary",
            summary: "Summary",
            trustFlags: .init(
                isGroundedInTranscript: false,
                containsSpeculation: false,
                isHumanReviewed: false,
                confidenceScore: 0.55,
            ),
        )
        let transcription = makeTranscription(canonicalSummary: summary)

        let decision = evaluator.evaluate(
            transcription: transcription,
            exportDestination: URL(fileURLWithPath: "/tmp"),
            candidateContent: "Valid content",
            policyLevel: .standard,
        )

        XCTAssertFalse(decision.isCompliant)
        XCTAssertTrue(decision.blockReasons.contains(where: { $0.code == SummaryExportBlockReason.Code.notGroundedInTranscript }))
        XCTAssertTrue(decision.blockReasons.contains(where: { $0.code == SummaryExportBlockReason.Code.confidenceBelowThreshold }))
    }

    func testEvaluateIsCompliantWhenPolicyRequirementsAreMet() {
        let evaluator = SummaryExportSafetyEvaluator()
        let summary = CanonicalSummary(
            title: "Summary",
            summary: "Summary",
            trustFlags: .init(
                isGroundedInTranscript: true,
                containsSpeculation: false,
                isHumanReviewed: false,
                confidenceScore: 0.92,
            ),
        )
        let transcription = makeTranscription(canonicalSummary: summary)

        let decision = evaluator.evaluate(
            transcription: transcription,
            exportDestination: URL(fileURLWithPath: "/tmp"),
            candidateContent: "Valid content",
            policyLevel: .strict,
        )

        XCTAssertTrue(decision.isCompliant)
        XCTAssertTrue(decision.blockReasons.isEmpty)
    }

    func testApplyRedactionIfNeeded() {
        let evaluator = SummaryExportSafetyEvaluator()
        let input = "Contact me at test@example.com and use token sk-abcdefghijklmnop"

        let strict = evaluator.applyRedactionIfNeeded(to: input, policyLevel: .strict)
        let permissive = evaluator.applyRedactionIfNeeded(to: input, policyLevel: .permissive)

        XCTAssertNotEqual(strict, input)
        XCTAssertTrue(strict.contains("[REDACTED_EMAIL]"))
        XCTAssertTrue(strict.contains("[REDACTED_SECRET]"))
        XCTAssertEqual(permissive, input)
    }

    func testAuditTrailWriterAppendsJsonlLines() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("summary-export-audit-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let writer = SummaryExportAuditTrailWriter(
            rootDirectoryURL: tempRoot,
        )

        let first = makeAuditEvent(outcome: .blocked)
        let second = makeAuditEvent(outcome: .exported)

        try writer.append(first)
        try writer.append(second)

        let files = try FileManager.default.contentsOfDirectory(at: tempRoot, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)

        let data = try Data(contentsOf: files[0])
        let text = try XCTUnwrap(String(bytes: data, encoding: .utf8))
        let lines = text.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
    }

    private func makeTranscription(canonicalSummary: CanonicalSummary?) -> CaptureArtifact {
        let meeting = CaptureSession(app: .googleMeet, type: .general)
        return CaptureArtifact(
            meeting: meeting,
            text: "Processed text",
            rawText: "Raw text",
            processedContent: "Processed text",
            canonicalSummary: canonicalSummary,
        )
    }

    private func makeAuditEvent(outcome: SummaryExportAuditOutcome) -> SummaryExportAuditEvent {
        SummaryExportAuditEvent(
            timestamp: Date(),
            transcriptionID: UUID(),
            meetingID: UUID(),
            outcome: outcome,
            policyLevel: .standard,
            blockReasonCodes: [],
            blockReasonMessages: [],
            requiredMinimumConfidence: 0.6,
            observedConfidence: 0.9,
            canonicalSummaryPresent: true,
            groundedInTranscript: true,
            redactionApplied: true,
            destinationPath: "/tmp/result.md",
            errorDescription: nil,
        )
    }
}

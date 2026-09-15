import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

@MainActor
public protocol SummaryExportHelperProtocol: Sendable {
    func exportAutomatically(transcription: Transcription) async
    func exportContentManually(_ content: String, to destinationURL: URL) throws
    func defaultExportFilename(for transcription: Transcription) -> String
}

@MainActor
public struct SummaryExportHelper: SummaryExportHelperProtocol {
    public init() {}

    public func exportAutomatically(transcription: Transcription) async {
        let settings = AppSettingsStore.shared
        let exportPolicyLevel = settings.summaryExportSafetyPolicyLevel

        let content = prepareExportContent(transcription: transcription, settings: settings)
        guard let content else { return }

        guard let folder = settings.summaryExportFolder else {
            let safetyDecision = evaluateExportSafety(
                transcription: transcription,
                destination: nil,
                settings: settings,
                content: content
            )
            await handleBlockedExport(
                transcription: transcription,
                safetyDecision: safetyDecision,
                exportPolicyLevel: exportPolicyLevel
            )
            return
        }

        let destinationURL = resolveExportDestinationURL(folder: folder, transcription: transcription)

        let safetyDecision = evaluateExportSafety(
            transcription: transcription,
            destination: destinationURL,
            settings: settings,
            content: content
        )

        guard safetyDecision.isCompliant else {
            await handleBlockedExport(
                transcription: transcription,
                safetyDecision: safetyDecision,
                exportPolicyLevel: exportPolicyLevel
            )
            return
        }

        do {
            try await performExport(
                destinationURL: destinationURL,
                isSecurityScoped: true,
                folderToUnlock: folder,
                transcription: transcription,
                content: content,
                safetyDecision: safetyDecision,
                exportPolicyLevel: exportPolicyLevel
            )
        } catch {
            AppLogger.error("Automatic summary export failed: \(error.localizedDescription)", category: .recordingManager)
        }
    }

    public func exportContentManually(_ content: String, to destinationURL: URL) throws {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            throw NSError(
                domain: "SummaryExportHelper",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "transcription.export.error.empty_content".localized]
            )
        }

        try ExportService().export(content: trimmedContent, to: destinationURL)
    }

    public func defaultExportFilename(for transcription: Transcription) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: transcription.meeting.startTime)

        let titleComponent = extractMeetingTitle(from: transcription)
        return "\(dateStr) \(titleComponent)"
    }

    // MARK: - Internal Helpers

    private func prepareExportContent(
        transcription: Transcription,
        settings: AppSettingsStore
    ) -> String? {
        if settings.summaryTemplateEnabled {
            let template = settings.summaryTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !template.isEmpty else {
                AppLogger.warning("Summary export blocked: template is empty", category: .security)
                return nil
            }
            return MarkdownRenderer().renderWithTemplate(template, meeting: transcription.meeting, transcription: transcription)
        } else {
            let plainContent = transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !plainContent.isEmpty else {
                AppLogger.warning("Summary export blocked: summary text is empty", category: .security)
                return nil
            }
            return plainContent
        }
    }

    private func evaluateExportSafety(
        transcription: Transcription,
        destination: URL?,
        settings: AppSettingsStore,
        content: String
    ) -> SummaryExportSafetyDecision {
        let safetyEvaluator = SummaryExportSafetyEvaluator()
        return safetyEvaluator.evaluate(
            transcription: transcription,
            exportDestination: destination,
            candidateContent: content,
            policyLevel: settings.summaryExportSafetyPolicyLevel
        )
    }

    private func handleBlockedExport(
        transcription: Transcription,
        safetyDecision: SummaryExportSafetyDecision,
        exportPolicyLevel: SummaryExportSafetyPolicyLevel
    ) {
        let reasons = safetyDecision.blockReasons.map(\.message).joined(separator: " | ")
        AppLogger.warning(
            "Summary export blocked by safety policy",
            category: .security,
            extra: [
                "policy": exportPolicyLevel.rawValue,
                "reasons": reasons
            ]
        )

        let blockedEvent = SummaryExportAuditEvent(
            timestamp: Date(),
            transcriptionID: transcription.id,
            meetingID: transcription.meeting.id,
            outcome: .blocked,
            policyLevel: exportPolicyLevel,
            blockReasonCodes: safetyDecision.blockReasons.map(\.code),
            blockReasonMessages: safetyDecision.blockReasons.map(\.message),
            requiredMinimumConfidence: safetyDecision.requiredMinimumConfidence,
            observedConfidence: safetyDecision.observedConfidence,
            canonicalSummaryPresent: transcription.canonicalSummary != nil,
            groundedInTranscript: transcription.canonicalSummary?.trustFlags.isGroundedInTranscript,
            redactionApplied: false,
            destinationPath: nil,
            errorDescription: nil
        )

        let auditTrailWriter = SummaryExportAuditTrailWriter()
        do {
            try auditTrailWriter.append(blockedEvent)
        } catch {
            AppLogger.error("Failed to append export audit event", category: .security, error: error)
        }
    }

    private func performExport(
        destinationURL: URL,
        isSecurityScoped: Bool,
        folderToUnlock: URL?,
        transcription: Transcription,
        content: String,
        safetyDecision: SummaryExportSafetyDecision,
        exportPolicyLevel: SummaryExportSafetyPolicyLevel
    ) throws {
        let safetyEvaluator = SummaryExportSafetyEvaluator()
        let redactionApplied = exportPolicyLevel.appliesSensitiveRedaction
        let exportContent = safetyEvaluator.applyRedactionIfNeeded(
            to: content,
            policyLevel: exportPolicyLevel
        )

        if isSecurityScoped, let folder = folderToUnlock {
            guard folder.startAccessingSecurityScopedResource() else {
                AppLogger.error("Failed to access export folder security-scoped resource", category: .recordingManager)
                return
            }
            defer { folder.stopAccessingSecurityScopedResource() }
            try tryWriteAndAudit(exportContent: exportContent, destinationURL: destinationURL, transcription: transcription, safetyDecision: safetyDecision, exportPolicyLevel: exportPolicyLevel, redactionApplied: redactionApplied)
        } else {
            try tryWriteAndAudit(exportContent: exportContent, destinationURL: destinationURL, transcription: transcription, safetyDecision: safetyDecision, exportPolicyLevel: exportPolicyLevel, redactionApplied: redactionApplied)
        }
    }

    private func tryWriteAndAudit(
        exportContent: String,
        destinationURL: URL,
        transcription: Transcription,
        safetyDecision: SummaryExportSafetyDecision,
        exportPolicyLevel: SummaryExportSafetyPolicyLevel,
        redactionApplied: Bool
    ) throws {
        let auditTrailWriter = SummaryExportAuditTrailWriter()

        do {
            try exportContent.write(to: destinationURL, atomically: true, encoding: .utf8)
            AppLogger.info("Summary exported to \(destinationURL.path)", category: .recordingManager)

            let successEvent = makeAuditEvent(
                transcription: transcription,
                outcome: .exported,
                policyLevel: exportPolicyLevel,
                safetyDecision: safetyDecision,
                redactionApplied: redactionApplied,
                destinationPath: destinationURL.path,
                error: nil
            )

            try auditTrailWriter.append(successEvent)
        } catch {
            AppLogger.error("Failed to export summary", category: .recordingManager, error: error)

            let writeFailureEvent = makeAuditEvent(
                transcription: transcription,
                outcome: .writeFailed,
                policyLevel: exportPolicyLevel,
                safetyDecision: safetyDecision,
                redactionApplied: redactionApplied,
                destinationPath: destinationURL.path,
                error: error
            )

            try? auditTrailWriter.append(writeFailureEvent)
            throw error
        }
    }

    private func resolveExportDestinationURL(
        folder: URL,
        transcription: Transcription
    ) -> URL {
        let baseName = defaultExportFilename(for: transcription)

        var destinationURL = folder.appendingPathComponent("\(baseName).md")
        var attempt = 1
        while FileManager.default.fileExists(atPath: destinationURL.path) {
            attempt += 1
            destinationURL = folder.appendingPathComponent("\(baseName)-\(attempt).md")
        }

        return destinationURL
    }

    private func extractMeetingTitle(from transcription: Transcription) -> String {
        transcription.meeting.resolvedTitle.components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:"))
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func makeAuditEvent(
        transcription: Transcription,
        outcome: SummaryExportAuditOutcome,
        policyLevel: SummaryExportSafetyPolicyLevel,
        safetyDecision: SummaryExportSafetyDecision,
        redactionApplied: Bool,
        destinationPath: String?,
        error: Error?
    ) -> SummaryExportAuditEvent {
        SummaryExportAuditEvent(
            timestamp: Date(),
            transcriptionID: transcription.id,
            meetingID: transcription.meeting.id,
            outcome: outcome,
            policyLevel: policyLevel,
            blockReasonCodes: outcome == .blocked ? safetyDecision.blockReasons.map(\.code) : [],
            blockReasonMessages: outcome == .blocked ? safetyDecision.blockReasons.map(\.message) : [],
            requiredMinimumConfidence: safetyDecision.requiredMinimumConfidence,
            observedConfidence: safetyDecision.observedConfidence,
            canonicalSummaryPresent: transcription.canonicalSummary != nil,
            groundedInTranscript: transcription.canonicalSummary?.trustFlags.isGroundedInTranscript,
            redactionApplied: redactionApplied,
            destinationPath: destinationPath,
            errorDescription: error?.localizedDescription
        )
    }
}

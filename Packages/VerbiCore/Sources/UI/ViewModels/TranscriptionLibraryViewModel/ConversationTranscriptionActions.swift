import AppKit
import Foundation
import OSLog
import SwiftUI
import VerbiCoreAI
import VerbiCoreAudio
import VerbiCoreCommon
import VerbiCoreData
import VerbiCoreDomain
import VerbiCoreInfrastructure

/// Data captured before the user confirms which vocabulary a retry should use.
public struct PendingRetryTranscription: Sendable, Equatable {
    public let metadata: TranscriptionMetadata
    public let selectionOverride: TranscriptionProviderSelection?
    public let originalVocabulary: VocabularySnapshot?
    public let originalVocabularySource: ExecutionVocabularySource?

    public init(
        metadata: TranscriptionMetadata,
        selectionOverride: TranscriptionProviderSelection?,
        originalVocabulary: VocabularySnapshot?,
        originalVocabularySource: ExecutionVocabularySource?
    ) {
        self.metadata = metadata
        self.selectionOverride = selectionOverride
        self.originalVocabulary = originalVocabulary
        self.originalVocabularySource = originalVocabularySource
    }

    /// A snapshot is authoritative only when the source recorded it. A
    /// reprocessed legacy artifact synthesizes an empty snapshot marked
    /// `notRecorded`, so the original option must fall back to the current
    /// dictionary instead of presenting an empty dictionary as historical.
    public var hasOriginalVocabulary: Bool {
        guard originalVocabulary != nil else { return false }
        return originalVocabularySource != .notRecorded
    }
}

public extension TranscriptionLibraryViewModel {
    enum ManualTranscriptionExportKind: Sendable {
        case summary
        case original

        var filenameSuffixKey: String? {
            switch self {
            case .summary:
                nil
            case .original:
                "transcription.export.filename.original_suffix"
            }
        }

        var emptyContentErrorKey: String {
            switch self {
            case .summary:
                "transcription.export.error.empty_summary"
            case .original:
                "transcription.export.error.empty_original"
            }
        }
    }

    static func manualExportSuggestedFilename(
        baseFilename: String,
        kind: ManualTranscriptionExportKind
    ) -> String {
        guard let suffixKey = kind.filenameSuffixKey else {
            return "\(baseFilename).md"
        }

        return "\(baseFilename) \(suffixKey.localized).md"
    }

    func exportTranscription(
        for metadata: TranscriptionMetadata,
        kind: ManualTranscriptionExportKind
    ) async {
        operationErrorMessage = nil
        do {
            guard let transcription = try await transcriptionForAction(metadata) else {
                operationErrorMessage = "transcription.export.error.missing_transcription".localized
                return
            }

            let exportContent = contentForManualExport(transcription: transcription, kind: kind)
            guard !exportContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                operationErrorMessage = kind.emptyContentErrorKey.localized
                return
            }

            let panel = savePanelProvider()
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = suggestedExportFilename(for: transcription, kind: kind)

            let response = panel.runModal()
            guard response == .OK, let destinationURL = panel.url else {
                return
            }

            try summaryExportHelper.exportContentManually(exportContent, to: destinationURL)
        } catch {
            logger.error("Failed to manually export transcription: \(error.localizedDescription)")
            operationErrorMessage = error.localizedDescription
        }
    }

    /// Validates the capture and opens the native confirmation that explains
    /// the two vocabulary intents before anything is overwritten.
    func requestRetryTranscription(
        for metadata: TranscriptionMetadata,
        selectionOverride: TranscriptionProviderSelection? = nil
    ) async {
        guard !recordingManager.isTranscribing else {
            return
        }

        operationErrorMessage = nil
        do {
            guard let transcription = try await transcriptionForAction(metadata) else {
                operationErrorMessage = "transcription.retry.missing_transcription".localized
                return
            }

            guard let audioURL = transcription.audioURL, FileManager.default.fileExists(atPath: audioURL.path) else {
                operationErrorMessage = "transcription.retry.missing_audio".localized
                return
            }

            pendingRetryTranscription = PendingRetryTranscription(
                metadata: metadata,
                selectionOverride: selectionOverride,
                originalVocabulary: transcription.executionProvenance?.vocabularySnapshot,
                originalVocabularySource: transcription.executionProvenance?.vocabularySource
            )
            showRetryConfirmation = true
        } catch {
            logger.error("Failed to prepare transcription retry: \(error.localizedDescription)")
            operationErrorMessage = error.localizedDescription
        }
    }

    func confirmRetryTranscription(vocabularyIntent: RetryVocabularyIntent) async {
        guard let pending = pendingRetryTranscription else { return }
        pendingRetryTranscription = nil
        showRetryConfirmation = false
        await retryTranscription(
            for: pending.metadata,
            selectionOverride: pending.selectionOverride,
            vocabularyIntent: vocabularyIntent
        )
    }

    func cancelRetryTranscription() {
        pendingRetryTranscription = nil
        showRetryConfirmation = false
    }

    func retryTranscription(
        for metadata: TranscriptionMetadata,
        selectionOverride: TranscriptionProviderSelection?,
        vocabularyIntent: RetryVocabularyIntent
    ) async {
        guard !recordingManager.isTranscribing else {
            return
        }

        do {
            guard let transcription = try await transcriptionForAction(metadata) else {
                operationErrorMessage = "transcription.retry.missing_transcription".localized
                return
            }

            guard let audioURL = transcription.audioURL, FileManager.default.fileExists(atPath: audioURL.path) else {
                operationErrorMessage = "transcription.retry.missing_audio".localized
                return
            }

            await recordingManager.retryTranscription(
                for: transcription,
                vocabularyIntent: vocabularyIntent,
                selectionOverride: selectionOverride
            )
            await loadTranscriptions()
            if selectedId == metadata.id {
                await loadFullTranscription(id: metadata.id)
            }
        } catch {
            logger.error("Failed to retry transcription: \(error.localizedDescription)")
            operationErrorMessage = error.localizedDescription
        }
    }

    func updateMeetingTitle(for metadata: TranscriptionMetadata, to title: String?) async {
        guard metadata.capturePurpose.supportsMeetingConversation else { return }

        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTitle = (trimmedTitle?.isEmpty == false) ? trimmedTitle : nil

        do {
            let existing = try await meetingRepository.fetchMeeting(by: metadata.meetingId)
            let updatedMeeting = makeUpdatedMeetingEntity(
                existing: existing,
                metadata: metadata,
                app: existing?.app ?? (CaptureOrigin(rawValue: metadata.appRawValue) ?? .unknown),
                capturePurpose: existing?.capturePurpose ?? metadata.capturePurpose,
                title: normalizedTitle
            )

            try await meetingRepository.updateMeeting(updatedMeeting)
            await loadTranscriptions()
            if selectedId == metadata.id {
                await loadFullTranscription(id: metadata.id)
            }
        } catch {
            logger.error("Failed to update meeting title: \(error.localizedDescription)")
            operationErrorMessage = error.localizedDescription
        }
    }

    func updateSource(for metadata: TranscriptionMetadata, isMeeting: Bool) async {
        await updateCapturePurpose(for: metadata, to: isMeeting ? .meeting : .dictation)
    }

    func updateCapturePurpose(for metadata: TranscriptionMetadata, to capturePurpose: CapturePurpose) async {
        let metadataApp = CaptureOrigin(rawValue: metadata.appRawValue) ?? .unknown

        do {
            let existing = try await meetingRepository.fetchMeeting(by: metadata.meetingId)
            let existingApp = existing?.app ?? metadataApp
            let endTime = metadata.duration > 0
                ? metadata.startTime.addingTimeInterval(metadata.duration)
                : nil
            let targetApp = adjustedApp(existingApp, for: capturePurpose)

            let updatedMeeting = makeUpdatedMeetingEntity(
                existing: existing,
                metadata: metadata,
                app: targetApp,
                capturePurpose: capturePurpose,
                title: capturePurpose == .meeting ? existing?.title ?? metadata.meetingTitle : nil,
                fallbackEndTime: endTime
            )

            try await meetingRepository.updateMeeting(updatedMeeting)
            await loadTranscriptions()
            if selectedId == metadata.id {
                await loadFullTranscription(id: metadata.id)
            }
        } catch {
            logger.error("Failed to update capture purpose: \(error.localizedDescription)")
            operationErrorMessage = error.localizedDescription
        }
    }

    private func transcriptionForAction(_ metadata: TranscriptionMetadata) async throws -> CaptureArtifact? {
        if selectedId == metadata.id, let current = selectedTranscription {
            return current
        }

        return try await storage.loadTranscription(by: metadata.id)
    }

    private func contentForManualExport(
        transcription: CaptureArtifact,
        kind: ManualTranscriptionExportKind
    ) -> String {
        switch kind {
        case .summary:
            TranscriptionDisplayText.preferredSummary(
                processedContent: transcription.processedContent,
                canonicalSummary: transcription.canonicalSummary,
                text: transcription.text,
                emptyFallback: ""
            )
        case .original:
            transcription.rawText
        }
    }

    private func suggestedExportFilename(
        for transcription: CaptureArtifact,
        kind: ManualTranscriptionExportKind
    ) -> String {
        let baseFilename = summaryExportHelper.defaultExportFilename(for: transcription)
        return Self.manualExportSuggestedFilename(baseFilename: baseFilename, kind: kind)
    }

    private func makeUpdatedMeetingEntity(
        existing: CaptureSessionEntity?,
        metadata: TranscriptionMetadata,
        app: CaptureOrigin,
        capturePurpose: CapturePurpose,
        title: String?,
        fallbackEndTime: Date? = nil
    ) -> CaptureSessionEntity {
        CaptureSessionEntity(
            id: metadata.meetingId,
            app: app,
            capturePurpose: capturePurpose,
            appBundleIdentifier: existing?.appBundleIdentifier ?? metadata.appBundleIdentifier,
            appDisplayName: existing?.appDisplayName ?? metadata.appName,
            title: title,
            linkedCalendarEvent: existing?.linkedCalendarEvent,
            startTime: existing?.startTime ?? metadata.startTime,
            endTime: existing?.endTime ?? fallbackEndTime,
            audioFilePath: existing?.audioFilePath ?? metadata.audioFilePath
        )
    }

    private func adjustedApp(_ app: CaptureOrigin, for capturePurpose: CapturePurpose) -> CaptureOrigin {
        switch (capturePurpose, app) {
        case (.meeting, .unknown):
            .manualMeeting
        case (.dictation, .manualMeeting):
            .unknown
        default:
            app
        }
    }
}

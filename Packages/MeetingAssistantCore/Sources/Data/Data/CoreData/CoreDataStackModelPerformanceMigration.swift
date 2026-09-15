import CoreData
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import os.log

extension CoreDataStack {
    public func backfillModelPerformanceAttemptsIfNeeded(
        checkpointKey: String? = nil
    ) async {
        let checkpointKey = checkpointKey ?? MigrationKeys.didBackfillModelPerformanceAttemptsV1
        guard !UserDefaults.standard.bool(forKey: checkpointKey) else { return }

        do {
            let backfilledCount = try await performBackgroundTask { context in
                try Self.backfillModelPerformanceAttempts(in: context)
            }
            UserDefaults.standard.set(true, forKey: checkpointKey)

            if backfilledCount > 0 {
                Logger(subsystem: AppIdentity.logSubsystem, category: "CoreData")
                    .notice("Backfilled \(backfilledCount) model performance attempts from persisted transcription snapshots")
            }
        } catch {
            Logger(subsystem: AppIdentity.logSubsystem, category: "CoreData")
                .error("Failed to backfill model performance attempts: \(error.localizedDescription)")
        }
    }

    private static func backfillModelPerformanceAttempts(
        in context: NSManagedObjectContext
    ) throws -> Int {
        let transcriptions = try context.fetch(TranscriptionMO.fetchRequest())
        guard !transcriptions.isEmpty else { return 0 }

        var insertedCount = 0
        for transcription in transcriptions {
            let existingAttempts = transcription.performanceAttempts
            let hasTranscriptionAttempt = existingAttempts.contains {
                $0.stageRawValue == ModelPerformanceStage.transcription.rawValue
            }
            if !hasTranscriptionAttempt {
                let attempt = syntheticTranscriptionAttempt(from: transcription)
                _ = ModelPerformanceAttemptMO.create(from: attempt, transcription: transcription, in: context)
                insertedCount += 1
            }

            let shouldBackfillPostProcessing = transcription.processedContent != nil
                || transcription.postProcessingDuration > 0
                || transcription.postProcessingModel != nil
            let hasPostProcessingAttempt = existingAttempts.contains {
                $0.stageRawValue == ModelPerformanceStage.postProcessing.rawValue
            }
            if shouldBackfillPostProcessing, !hasPostProcessingAttempt {
                let attempt = syntheticPostProcessingAttempt(from: transcription)
                _ = ModelPerformanceAttemptMO.create(from: attempt, transcription: transcription, in: context)
                insertedCount += 1
            }
        }

        if insertedCount > 0 {
            try context.save()
        }
        return insertedCount
    }

    private static func syntheticTranscriptionAttempt(from transcription: TranscriptionMO) -> ModelPerformanceAttempt {
        let identity = inferredTranscriptionIdentity(from: transcription)
        let postProcessingSeconds = max(0, transcription.postProcessingDuration)
        let completedAt = transcription.createdAt.addingTimeInterval(-postProcessingSeconds)
        let startedAt = completedAt.addingTimeInterval(-max(0, transcription.transcriptionDuration))

        return ModelPerformanceAttempt(
            transcriptionID: transcription.id,
            stage: .transcription,
            attemptKind: .initial,
            capturePurpose: CapturePurpose(rawValue: transcription.meeting.capturePurposeRawValue ?? "") ?? .meeting,
            modelIdentity: identity,
            status: TranscriptionLifecycleState(rawValue: transcription.lifecycleStateRawValue) == .failed ? .failed : .succeeded,
            startedAt: startedAt,
            completedAt: completedAt,
            wallClockSeconds: max(0, transcription.transcriptionDuration),
            audioSeconds: max(0, transcription.meeting.endTime?.timeIntervalSince(transcription.meeting.startTime) ?? 0),
            inputUTF8Bytes: 0,
            inputCharacterCount: 0,
            outputCharacterCount: transcription.text.count,
            failureReason: nil
        )
    }

    private static func syntheticPostProcessingAttempt(from transcription: TranscriptionMO) -> ModelPerformanceAttempt {
        let identity = inferredPostProcessingIdentity(from: transcription)
        let completedAt = transcription.createdAt
        let startedAt = completedAt.addingTimeInterval(-max(0, transcription.postProcessingDuration))
        let inputText = transcription.rawText

        return ModelPerformanceAttempt(
            transcriptionID: transcription.id,
            stage: .postProcessing,
            attemptKind: .initial,
            capturePurpose: CapturePurpose(rawValue: transcription.meeting.capturePurposeRawValue ?? "") ?? .meeting,
            modelIdentity: identity,
            status: transcription.processedContent == nil ? .failed : .succeeded,
            startedAt: startedAt,
            completedAt: completedAt,
            wallClockSeconds: max(0, transcription.postProcessingDuration),
            audioSeconds: 0,
            inputUTF8Bytes: inputText.lengthOfBytes(using: .utf8),
            inputCharacterCount: inputText.count,
            outputCharacterCount: transcription.processedContent?.count ?? 0,
            failureReason: nil
        )
    }

    private static func inferredTranscriptionIdentity(from transcription: TranscriptionMO) -> ModelPerformanceModelIdentity {
        let modelID = transcription.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let capturePurpose = CapturePurpose(rawValue: transcription.meeting.capturePurposeRawValue ?? "") ?? .meeting

        if capturePurpose == .meeting || LocalTranscriptionModel(rawValue: modelID) != nil {
            let provider = TranscriptionProvider.local
            return ModelPerformanceModelIdentity(
                providerID: provider.rawValue,
                providerDisplayName: provider.displayName,
                modelID: modelID,
                modelDisplayName: provider.displayName(forModelID: modelID),
                runtimeKind: .local
            )
        }

        if TranscriptionProvider.groqPresetModelIDs.contains(modelID) {
            let provider = TranscriptionProvider.groq
            return ModelPerformanceModelIdentity(
                providerID: provider.rawValue,
                providerDisplayName: provider.displayName,
                modelID: modelID,
                modelDisplayName: provider.displayName(forModelID: modelID),
                runtimeKind: .remote
            )
        }

        if TranscriptionProvider.elevenLabsPresetModelIDs.contains(modelID) {
            let provider = TranscriptionProvider.elevenLabs
            return ModelPerformanceModelIdentity(
                providerID: provider.rawValue,
                providerDisplayName: provider.displayName,
                modelID: modelID,
                modelDisplayName: provider.displayName(forModelID: modelID),
                runtimeKind: .remote
            )
        }

        return ModelPerformanceModelIdentity(
            providerID: "unknown",
            providerDisplayName: "Unknown",
            modelID: modelID.isEmpty ? "unknown" : modelID,
            modelDisplayName: modelID.isEmpty ? "Unknown" : modelID,
            runtimeKind: .unknown
        )
    }

    private static func inferredPostProcessingIdentity(from transcription: TranscriptionMO) -> ModelPerformanceModelIdentity {
        let modelID = transcription.postProcessingModel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
        let provider = inferredEnhancementsProvider(from: modelID)

        if let provider {
            return ModelPerformanceModelIdentity(
                providerID: provider.rawValue,
                providerDisplayName: provider.displayName,
                modelID: modelID,
                modelDisplayName: modelID,
                runtimeKind: .remote
            )
        }

        return ModelPerformanceModelIdentity(
            providerID: "unknown",
            providerDisplayName: "Unknown",
            modelID: modelID,
            modelDisplayName: modelID,
            runtimeKind: .unknown
        )
    }

    private static func inferredEnhancementsProvider(from modelID: String) -> AIProvider? {
        let normalized = modelID.lowercased()
        if normalized.hasPrefix("gpt") || normalized.hasPrefix("o1") || normalized.hasPrefix("o3") || normalized.hasPrefix("o4") {
            return .openai
        }
        if normalized.hasPrefix("claude") {
            return .anthropic
        }
        if normalized.hasPrefix("gemini") {
            return .google
        }
        return nil
    }
}

import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

// swiftlint:disable function_body_length

// MARK: - Transcription Entities

extension RecordingManager {
    func makeMeetingEntity(meeting: Meeting, audioDuration: Double?) -> MeetingEntity {
        var entity = MeetingEntity(
            id: meeting.id,
            app: DomainMeetingApp(rawValue: meeting.app.rawValue) ?? .unknown,
            capturePurpose: meeting.capturePurpose,
            appBundleIdentifier: meeting.appBundleIdentifier,
            appDisplayName: meeting.appDisplayName,
            title: meeting.title,
            linkedCalendarEvent: meeting.linkedCalendarEvent,
            startTime: meeting.startTime,
            endTime: meeting.endTime,
            audioFilePath: meeting.audioFilePath
        )

        if entity.endTime == nil, let audioDuration {
            entity.endTime = entity.startTime.addingTimeInterval(audioDuration)
        }

        return entity
    }

    func convertToModel(_ entity: TranscriptionEntity, audioDuration _: Double?, transcriptionStart _: Date) -> Transcription {
        Transcription(
            id: entity.id,
            meeting: Meeting(
                id: entity.meeting.id,
                app: MeetingApp(rawValue: entity.meeting.app.rawValue) ?? .unknown,
                capturePurpose: entity.meeting.capturePurpose,
                appBundleIdentifier: entity.meeting.appBundleIdentifier,
                appDisplayName: entity.meeting.appDisplayName,
                title: entity.meeting.title,
                linkedCalendarEvent: entity.meeting.linkedCalendarEvent,
                type: MeetingType(rawValue: entity.meetingType ?? "") ?? .general,
                startTime: entity.meeting.startTime,
                endTime: entity.meeting.endTime,
                audioFilePath: entity.meeting.audioFilePath
            ),
            contextItems: entity.contextItems,
            segments: entity.segments.map {
                Transcription.Segment(
                    id: $0.id,
                    speaker: $0.speaker,
                    text: $0.text,
                    startTime: $0.startTime,
                    endTime: $0.endTime
                )
            },
            text: entity.text,
            rawText: entity.rawText,
            processedContent: entity.processedContent,
            canonicalSummary: entity.canonicalSummary,
            qualityProfile: entity.qualityProfile,
            postProcessingPromptId: entity.postProcessingPromptId,
            postProcessingPromptTitle: entity.postProcessingPromptTitle,
            postProcessingRequestSystemPrompt: entity.postProcessingRequestSystemPrompt,
            postProcessingRequestUserPrompt: entity.postProcessingRequestUserPrompt,
            language: entity.language,
            createdAt: entity.createdAt,
            modelName: entity.modelName,
            inputSource: entity.inputSource,
            transcriptionDuration: entity.transcriptionDuration,
            postProcessingDuration: entity.postProcessingDuration,
            postProcessingModel: entity.postProcessingModel,
            meetingType: entity.meetingType,
            lifecycleState: entity.lifecycleState,
            postProcessingFailureReason: entity.postProcessingFailureReason,
            postProcessingOutputState: entity.postProcessingOutputState,
            transcriptionFailureReason: entity.transcriptionFailureReason,
            executionProvenance: entity.executionProvenance
        )
    }

    func persistFailedTranscriptionAttempt(
        audioURL _: URL,
        persistedAudioURL: URL,
        session: TranscriptionSessionSnapshot,
        audioDuration: Double?,
        transcriptionIDOverride: UUID?,
        error: Error
    ) async {
        let startedAt = session.meeting.startTime
        var failedMeeting = session.meeting
        failedMeeting.audioFilePath = persistedAudioURL.path
        if failedMeeting.endTime == nil, let audioDuration {
            failedMeeting.endTime = startedAt.addingTimeInterval(audioDuration)
        }

        let transcriptionIdentity = resolvedTranscriptionPerformanceIdentity(
            capturePurpose: session.meeting.capturePurpose,
            configuration: session.transcriptionConfiguration
        )
        let failureDate = Date()
        let failedTranscription = Transcription(
            id: transcriptionIDOverride ?? UUID(),
            meeting: failedMeeting,
            contextItems: session.postProcessingContextItems,
            segments: [],
            text: "",
            rawText: "",
            processedContent: nil,
            canonicalSummary: nil,
            qualityProfile: nil,
            postProcessingPromptId: nil,
            postProcessingPromptTitle: nil,
            postProcessingRequestSystemPrompt: nil,
            postProcessingRequestUserPrompt: nil,
            language: Locale.current.language.languageCode?.identifier ?? "und",
            createdAt: Date(),
            modelName: session.transcriptionConfiguration?.modelID
                ?? AppSettingsStore.shared.resolvedTranscriptionSelection(
                    for: session.meeting.capturePurpose.transcriptionExecutionMode
                ).selectedModel,
            inputSource: resolveInputSourceLabel(
                for: session.meeting,
                recordingSource: session.recordingSource
            ),
            transcriptionDuration: 0,
            postProcessingDuration: 0,
            postProcessingModel: nil,
            meetingType: session.meeting.type.rawValue,
            lifecycleState: .failed,
            meetingConversationState: nil,
            postProcessingFailureReason: nil,
            postProcessingOutputState: nil,
            transcriptionFailureReason: transcriptionStatusError(from: error).localizedDescription,
            executionProvenance: session.transcriptionConfiguration.map {
                ExecutionProvenance(
                    transcriptionRequest: $0,
                    vocabularySnapshot: session.vocabularySnapshot,
                    transcriptionModelIdentity: transcriptionIdentity,
                    kernelMode: session.kernelMode
                )
            }
        )

        do {
            try await storage.saveTranscription(failedTranscription)
            let failedAttempt = ModelPerformanceAttempt(
                transcriptionID: failedTranscription.id,
                stage: .transcription,
                attemptKind: .initial,
                capturePurpose: failedTranscription.capturePurpose,
                modelIdentity: transcriptionIdentity,
                status: .failed,
                startedAt: startedAt,
                completedAt: failureDate,
                wallClockSeconds: max(0, failureDate.timeIntervalSince(startedAt)),
                audioSeconds: max(0, audioDuration ?? failedMeeting.duration),
                inputUTF8Bytes: 0,
                inputCharacterCount: 0,
                outputCharacterCount: 0,
                failureReason: transcriptionStatusError(from: error).localizedDescription,
                executionProvenance: failedTranscription.executionProvenance
            )
            try? await storage.saveModelPerformanceAttempt(failedAttempt)
            NotificationCenter.default.post(
                name: .meetingAssistantTranscriptionSaved,
                object: nil,
                userInfo: [AppNotifications.UserInfoKey.transcriptionId: failedTranscription.id.uuidString]
            )
        } catch {
            AppLogger.error(
                "Failed to persist failed transcription attempt",
                category: .recordingManager,
                error: error,
                extra: ["sessionID": session.id.uuidString]
            )
        }
    }

    func persistedAudioURL(
        transcriptionURL: URL,
        cleanupAudioURL: URL?,
        session: TranscriptionSessionSnapshot
    ) -> URL {
        guard cleanupAudioURL == transcriptionURL,
              let originalPath = session.meeting.audioFilePath
        else {
            return transcriptionURL
        }
        return URL(fileURLWithPath: originalPath)
    }
}

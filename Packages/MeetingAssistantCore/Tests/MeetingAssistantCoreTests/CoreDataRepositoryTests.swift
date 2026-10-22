// CoreDataRepositoryTests - Testes de integração para repositórios CoreData
// Usa banco de dados em memória para isolamento

import CoreData
@testable import MeetingAssistantCore
import XCTest

// swiftlint:disable:next type_body_length
final class CoreDataRepositoryTests: XCTestCase {
    var stack: CoreDataStack!
    var meetingRepo: CoreDataMeetingRepository!
    var transcriptionRepo: CoreDataTranscriptionStorageRepository!

    override func setUp() {
        super.setUp()
        // Usar banco em memória para testes
        stack = CoreDataStack(name: "MeetingAssistantTests", inMemory: true)
        meetingRepo = CoreDataMeetingRepository(stack: stack)
        transcriptionRepo = CoreDataTranscriptionStorageRepository(stack: stack)
    }

    override func tearDown() {
        stack = nil
        meetingRepo = nil
        transcriptionRepo = nil
        super.tearDown()
    }

    // MARK: - Meeting Repository Tests

    func testSaveAndFetchMeeting() async throws {
        // Given
        let meeting = MeetingEntity(
            id: UUID(),
            app: .slack,
            startTime: Date(),
            audioFilePath: "/tmp/test.wav",
        )

        // When
        try await meetingRepo.saveMeeting(meeting)
        let fetched = try await meetingRepo.fetchMeeting(by: meeting.id)

        // Then
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, meeting.id)
        XCTAssertEqual(fetched?.app, .slack)
        XCTAssertEqual(fetched?.audioFilePath, "/tmp/test.wav")
    }

    func testFetchAllMeetings() async throws {
        // Given
        let m1 = MeetingEntity(app: .zoom)
        let m2 = MeetingEntity(app: .microsoftTeams)
        try await meetingRepo.saveMeeting(m1)
        try await meetingRepo.saveMeeting(m2)

        // When
        let all = try await meetingRepo.fetchAllMeetings()

        // Then
        XCTAssertEqual(all.count, 2)
    }

    func testDeleteMeeting() async throws {
        // Given
        let meeting = MeetingEntity(app: .slack)
        try await meetingRepo.saveMeeting(meeting)

        // When
        try await meetingRepo.deleteMeeting(by: meeting.id)
        let fetched = try await meetingRepo.fetchMeeting(by: meeting.id)

        // Then
        XCTAssertNil(fetched)
    }

    func testSaveMeeting_ClearsTitleAndCalendarLinkForNonMeetingApps() async throws {
        let meeting = MeetingEntity(
            id: UUID(),
            app: .importedFile,
            title: "Imported title",
            linkedCalendarEvent: MeetingCalendarEventSnapshot(
                eventIdentifier: "calendar-1",
                title: "Calendar title",
                startDate: Date(),
                endDate: Date().addingTimeInterval(3_600),
                location: "Room",
                notes: "Notes",
                attendees: ["Alice"],
            ),
            startTime: Date(),
        )

        try await meetingRepo.saveMeeting(meeting)
        let fetched = try await meetingRepo.fetchMeeting(by: meeting.id)

        XCTAssertNotNil(fetched)
        XCTAssertNil(fetched?.title)
        XCTAssertNil(fetched?.linkedCalendarEvent)
        XCTAssertNil(fetched?.preferredTitle)
    }

    func testSaveMeeting_PreservesTitleForImportedMeeting() async throws {
        let meeting = MeetingEntity(
            app: .importedFile,
            capturePurpose: .meeting,
            title: "Imported planning call",
            startTime: Date(),
        )

        try await meetingRepo.saveMeeting(meeting)
        let fetched = try await meetingRepo.fetchMeeting(by: meeting.id)

        XCTAssertEqual(fetched?.capturePurpose, .meeting)
        XCTAssertEqual(fetched?.preferredTitle, "Imported planning call")
        XCTAssertTrue(fetched?.capturePurpose.supportsMeetingConversation == true)
    }

    func testSanitizeMeetingOnlyPresentationDataIfNeeded_CleansLegacyNonMeetingRows() async throws {
        let checkpointKey = "coredata.tests.non_meeting_sanitizer.\(UUID().uuidString)"
        UserDefaults.standard.removeObject(forKey: checkpointKey)
        defer { UserDefaults.standard.removeObject(forKey: checkpointKey) }

        let meetingID = UUID()
        try await stack.performBackgroundTask { context in
            guard let entityDescription = NSEntityDescription.entity(forEntityName: "MeetingMO", in: context) else {
                preconditionFailure("Missing Core Data entity description for MeetingMO")
            }
            let meeting = MeetingMO(
                entity: entityDescription,
                insertInto: context,
            )
            meeting.id = meetingID
            meeting.appRawValue = DomainMeetingApp.importedFile.rawValue
            meeting.title = "Legacy imported title"
            meeting.linkedCalendarEventData = try JSONEncoder().encode(
                MeetingCalendarEventSnapshot(
                    eventIdentifier: "calendar-legacy",
                    title: "Legacy calendar title",
                    startDate: Date(),
                    endDate: Date().addingTimeInterval(3_600),
                    attendees: [],
                ),
            )
            meeting.startTime = Date()
            try context.save()
        }

        await stack.sanitizeMeetingOnlyPresentationDataIfNeeded(checkpointKey: checkpointKey)
        let fetched = try await meetingRepo.fetchMeeting(by: meetingID)

        XCTAssertNotNil(fetched)
        XCTAssertNil(fetched?.title)
        XCTAssertNil(fetched?.linkedCalendarEvent)
        XCTAssertNil(fetched?.preferredTitle)
    }

    func testSanitizeMockTranscriptionArtifactsIfNeeded_RemovesPersistedMockRows() async throws {
        let checkpointKey = "coredata.tests.mock_artifact_sanitizer.\(UUID().uuidString)"
        UserDefaults.standard.removeObject(forKey: checkpointKey)
        defer { UserDefaults.standard.removeObject(forKey: checkpointKey) }

        let meeting = MeetingEntity(app: .unknown, capturePurpose: .dictation)
        try await meetingRepo.saveMeeting(meeting)

        var config = TranscriptionEntity.Configuration(
            text: TranscriptionMO.mockArtifactDefaultText,
            rawText: TranscriptionMO.mockArtifactDefaultText,
        )
        config.modelName = TranscriptionMO.mockArtifactDefaultModel
        let transcription = TranscriptionEntity(meeting: meeting, config: config)

        try await transcriptionRepo.saveTranscription(transcription)
        let persistedMetadata = try await transcriptionRepo.fetchAllMetadata()
        XCTAssertEqual(persistedMetadata.count, 1)

        await stack.sanitizeMockTranscriptionArtifactsIfNeeded(checkpointKey: checkpointKey)

        let sanitizedMetadata = try await transcriptionRepo.fetchAllMetadata()
        let sanitizedTranscription = try await transcriptionRepo.fetchTranscription(by: transcription.id)
        XCTAssertTrue(sanitizedMetadata.isEmpty)
        XCTAssertNil(sanitizedTranscription)
    }

    // MARK: - Transcription Repository Tests

    func testSaveAndFetchTranscription() async throws {
        // Given
        let meeting = MeetingEntity(app: .googleMeet)
        try await meetingRepo.saveMeeting(meeting)

        let config = TranscriptionEntity.Configuration(
            text: "Hi",
            rawText: "Hi",
            segments: [
                TranscriptionEntity.Segment(speaker: "A", text: "Hi", startTime: 0, endTime: 1),
            ],
        )
        let transcription = TranscriptionEntity(meeting: meeting, config: config)

        // When
        try await transcriptionRepo.saveTranscription(transcription)
        let fetched = try await transcriptionRepo.fetchTranscription(by: transcription.id)

        // Then
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, transcription.id)
        XCTAssertEqual(fetched?.meeting.id, meeting.id)
        XCTAssertEqual(fetched?.segments.count, 1)
        XCTAssertEqual(fetched?.segments.first?.text, "Hi")
    }

    func testSaveAndFetchTranscription_PreservesExecutionProvenance() async throws {
        let meeting = MeetingEntity(app: .googleMeet)
        try await meetingRepo.saveMeeting(meeting)
        let provenance = ExecutionProvenance(
            transcriptionRequest: DomainTranscriptionRequestConfiguration(
                providerID: "local",
                modelID: "model-a",
                inputLanguageCode: "pt",
            ),
            vocabularySnapshot: .empty,
            transcriptionModelIdentity: ModelPerformanceModelIdentity(
                providerID: "local",
                providerDisplayName: "Local",
                modelID: "model-a",
                modelDisplayName: "Model A",
                runtimeKind: .local,
            ),
        )
        var config = TranscriptionEntity.Configuration(text: "Hi", rawText: "Hi")
        config.executionProvenance = provenance
        let transcription = TranscriptionEntity(meeting: meeting, config: config)

        try await transcriptionRepo.saveTranscription(transcription)

        let fetched = try await transcriptionRepo.fetchTranscription(by: transcription.id)
        XCTAssertEqual(fetched?.executionProvenance, provenance)
    }

    func testExecutionProvenanceSchemaIsOptionalBinaryForIncrementalMigration() throws {
        let model = CoreDataModel.createManagedObjectModel()

        for entityName in ["TranscriptionMO", "ModelPerformanceAttemptMO"] {
            let entity = try XCTUnwrap(model.entitiesByName[entityName])
            let attribute = try XCTUnwrap(entity.attributesByName["executionProvenanceData"])
            XCTAssertEqual(attribute.attributeType, .binaryDataAttributeType)
            XCTAssertTrue(attribute.isOptional)
            XCTAssertTrue(attribute.allowsExternalBinaryDataStorage)
        }

        XCTAssertEqual(CoreDataModel.currentVersion, "1.6")
    }

    func testCorruptExecutionProvenance_IsIgnoredForTranscriptionAndAttempt() async throws {
        let meeting = MeetingEntity(app: .unknown, capturePurpose: .dictation)
        try await meetingRepo.saveMeeting(meeting)
        let transcription = TranscriptionEntity(
            meeting: meeting,
            config: .init(text: "Raw text", rawText: "Raw text"),
        )
        try await transcriptionRepo.saveTranscription(transcription)
        try await transcriptionRepo.saveModelPerformanceAttempt(
            makeAttempt(
                transcriptionID: transcription.id,
                providerID: "local",
                modelID: "model-a",
                startedAt: Date(),
                executionProvenance: ExecutionProvenance(
                    transcriptionRequest: .init(providerID: "local", modelID: "model-a", inputLanguageCode: "pt"),
                    vocabularySnapshot: .empty,
                    transcriptionModelIdentity: .init(
                        providerID: "local",
                        providerDisplayName: "Local",
                        modelID: "model-a",
                        modelDisplayName: "Model A",
                        runtimeKind: .local,
                    ),
                ),
            ),
        )

        try await stack.performBackgroundTask { context in
            let transcriptionMO = try XCTUnwrap(
                context.fetch(TranscriptionMO.fetchRequest(forTranscriptionId: transcription.id)).first,
            )
            transcriptionMO.executionProvenanceData = Data([0x00, 0x01, 0x02])

            let attemptMO = try XCTUnwrap(
                context.fetch(ModelPerformanceAttemptMO.fetchRequest(forTranscriptionID: transcription.id)).first,
            )
            attemptMO.executionProvenanceData = Data([0x03, 0x04, 0x05])
            try context.save()
        }

        let fetchedTranscription = try await transcriptionRepo.fetchTranscription(by: transcription.id)
        let fetchedAttempts = try await transcriptionRepo.fetchModelPerformanceAttempts(
            matching: .init(stage: .transcription),
        )
        XCTAssertNil(fetchedTranscription?.executionProvenance)
        XCTAssertNil(fetchedAttempts.first?.executionProvenance)
    }

    func testLoadMetadata_AppliesNewestSortAndLimit() async throws {
        let storage = FileSystemStorageService(
            honorsConfiguredRecordingDirectory: false,
            coreDataStack: stack,
        )
        let now = Date()

        for offset in 0..<3 {
            let meeting = MeetingEntity(
                app: .zoom,
                capturePurpose: .meeting,
                startTime: now.addingTimeInterval(TimeInterval(-offset * 60)),
            )
            try await meetingRepo.saveMeeting(meeting)

            var configuration = TranscriptionEntity.Configuration(
                text: "Transcription " + String(offset),
                rawText: "Transcription " + String(offset),
            )
            configuration.createdAt = now.addingTimeInterval(TimeInterval(-offset * 60))
            try await transcriptionRepo.saveTranscription(
                TranscriptionEntity(meeting: meeting, config: configuration),
            )
        }

        let results = try await storage.loadMetadata(
            matching: TranscriptionMetadataQuery(limit: 2),
        )

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.map(\.previewText), ["Transcription 0", "Transcription 1"])
        XCTAssertGreaterThanOrEqual(results[0].createdAt, results[1].createdAt)
    }

    func testSaveAndFetchTranscription_WithCanonicalSummary() async throws {
        // Given
        let meeting = MeetingEntity(app: .googleMeet)
        try await meetingRepo.saveMeeting(meeting)

        let summary = CanonicalSummary(
            title: "Project Status",
            summary: "Project status is on track.",
            keyPoints: ["Milestone A completed"],
            decisions: ["Ship beta next week"],
            actionItems: [.init(title: "Prepare release notes", owner: "PM")],
            openQuestions: ["Do we need a migration guide?"],
            trustFlags: .init(
                isGroundedInTranscript: true,
                containsSpeculation: false,
                isHumanReviewed: true,
                confidenceScore: 0.92,
            ),
        )

        var config = TranscriptionEntity.Configuration(text: "Raw text", rawText: "Raw text")
        config.canonicalSummary = summary
        let transcription = TranscriptionEntity(meeting: meeting, config: config)

        // When
        try await transcriptionRepo.saveTranscription(transcription)
        let fetched = try await transcriptionRepo.fetchTranscription(by: transcription.id)

        // Then
        XCTAssertEqual(fetched?.canonicalSummary?.schemaVersion, CanonicalSummary.currentSchemaVersion)
        XCTAssertEqual(fetched?.canonicalSummary?.summary, "Project status is on track.")
        XCTAssertEqual(fetched?.canonicalSummary?.trustFlags.isGroundedInTranscript, true)
        XCTAssertEqual(fetched?.canonicalSummary?.trustFlags.confidenceScore ?? -1, 0.92, accuracy: 0.001)
    }

    func testSaveAndFetchTranscription_PreservesRequestPrompts() async throws {
        let meeting = MeetingEntity(app: .unknown, capturePurpose: .dictation)
        try await meetingRepo.saveMeeting(meeting)

        var config = TranscriptionEntity.Configuration(
            text: "Processed text",
            rawText: "Raw text",
        )
        config.postProcessingPromptId = UUID()
        config.postProcessingPromptTitle = "Dictation Prompt"
        config.postProcessingRequestSystemPrompt = "System prompt payload"
        config.postProcessingRequestUserPrompt = "User prompt payload"

        let transcription = TranscriptionEntity(meeting: meeting, config: config)
        try await transcriptionRepo.saveTranscription(transcription)

        let fetched = try await transcriptionRepo.fetchTranscription(by: transcription.id)
        XCTAssertEqual(fetched?.postProcessingRequestSystemPrompt, "System prompt payload")
        XCTAssertEqual(fetched?.postProcessingRequestUserPrompt, "User prompt payload")
    }

    func testFetchModelPerformanceAttempts_BackfillsSyntheticAttemptsFromLegacySnapshot() async throws {
        let checkpointKey = "coredata.tests.model_performance_backfill.\(UUID().uuidString)"
        UserDefaults.standard.removeObject(forKey: checkpointKey)
        defer { UserDefaults.standard.removeObject(forKey: checkpointKey) }

        let meeting = MeetingEntity(app: .unknown, capturePurpose: .dictation)
        try await meetingRepo.saveMeeting(meeting)

        var config = TranscriptionEntity.Configuration(
            text: "Processed text",
            rawText: "Raw text",
        )
        config.modelName = "legacy-transcriber"
        config.transcriptionDuration = 42
        config.processedContent = "Processed text"
        config.postProcessingDuration = 5
        config.postProcessingModel = "legacy-cleaner"
        let transcription = TranscriptionEntity(meeting: meeting, config: config)

        try await transcriptionRepo.saveTranscription(transcription)
        await stack.backfillModelPerformanceAttemptsIfNeeded(checkpointKey: checkpointKey)

        let transcriptionAttempts = try await transcriptionRepo.fetchModelPerformanceAttempts(
            matching: ModelPerformanceAttemptQuery(stage: .transcription),
        )
        let postProcessingAttempts = try await transcriptionRepo.fetchModelPerformanceAttempts(
            matching: ModelPerformanceAttemptQuery(stage: .postProcessing),
        )

        XCTAssertEqual(transcriptionAttempts.count, 1)
        XCTAssertEqual(postProcessingAttempts.count, 1)
        XCTAssertEqual(transcriptionAttempts.first?.modelIdentity.providerID, "unknown")
        XCTAssertEqual(transcriptionAttempts.first?.modelIdentity.runtimeKind, .unknown)
        XCTAssertEqual(postProcessingAttempts.first?.modelIdentity.providerID, "unknown")
        XCTAssertEqual(postProcessingAttempts.first?.modelIdentity.runtimeKind, .unknown)
    }

    func testFetchModelPerformanceAttempts_ReturnsNewestAttemptsFirstAndHonorsLimit() async throws {
        let meeting = MeetingEntity(app: .unknown, capturePurpose: .dictation)
        try await meetingRepo.saveMeeting(meeting)

        var config = TranscriptionEntity.Configuration(
            text: "Raw text",
            rawText: "Raw text",
        )
        config.modelName = "test-model"
        let transcription = TranscriptionEntity(meeting: meeting, config: config)
        try await transcriptionRepo.saveTranscription(transcription)

        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        try await transcriptionRepo.saveModelPerformanceAttempt(
            makeAttempt(
                transcriptionID: transcription.id,
                providerID: "local",
                modelID: "model-a",
                startedAt: baseDate,
            ),
        )
        try await transcriptionRepo.saveModelPerformanceAttempt(
            makeAttempt(
                transcriptionID: transcription.id,
                providerID: "local",
                modelID: "model-a",
                startedAt: baseDate.addingTimeInterval(10),
            ),
        )
        try await transcriptionRepo.saveModelPerformanceAttempt(
            makeAttempt(
                transcriptionID: transcription.id,
                providerID: "local",
                modelID: "model-a",
                startedAt: baseDate.addingTimeInterval(20),
            ),
        )

        let attempts = try await transcriptionRepo.fetchModelPerformanceAttempts(
            matching: ModelPerformanceAttemptQuery(stage: .transcription, limit: 2),
        )

        XCTAssertEqual(attempts.count, 2)
        XCTAssertEqual(attempts.map(\.startedAt), [baseDate.addingTimeInterval(20), baseDate.addingTimeInterval(10)])
    }

    func testModelPerformanceAttemptsKeepDistinctExecutionProvenance() async throws {
        let meeting = MeetingEntity(app: .unknown, capturePurpose: .dictation)
        try await meetingRepo.saveMeeting(meeting)
        let transcription = TranscriptionEntity(
            meeting: meeting,
            config: .init(text: "Raw text", rawText: "Raw text"),
        )
        try await transcriptionRepo.saveTranscription(transcription)

        func provenance(_ modelID: String) -> ExecutionProvenance {
            ExecutionProvenance(
                transcriptionRequest: .init(providerID: "local", modelID: modelID, inputLanguageCode: "pt"),
                vocabularySnapshot: .empty,
                transcriptionModelIdentity: .init(
                    providerID: "local",
                    providerDisplayName: "Local",
                    modelID: modelID,
                    modelDisplayName: modelID,
                    runtimeKind: .local,
                ),
            )
        }

        let attemptA = makeAttempt(
            transcriptionID: transcription.id,
            providerID: "local",
            modelID: "model-a",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            executionProvenance: provenance("model-a"),
        )
        try await transcriptionRepo.saveModelPerformanceAttempt(attemptA)
        let attemptB = makeAttempt(
            transcriptionID: transcription.id,
            providerID: "local",
            modelID: "model-b",
            startedAt: Date(timeIntervalSince1970: 1_700_000_010),
            executionProvenance: provenance("model-b"),
        )
        try await transcriptionRepo.saveModelPerformanceAttempt(attemptB)

        let attempts = try await transcriptionRepo.fetchModelPerformanceAttempts(
            matching: .init(stage: .transcription),
        )
        XCTAssertEqual(Set(attempts.compactMap { $0.executionProvenance?.transcriptionRequest?.modelID }), Set(["model-a", "model-b"]))
    }

    func testSaveTranscription_NonMeetingMetadataDoesNotExposeTitleOrCalendarFallback() async throws {
        let meeting = MeetingEntity(
            id: UUID(),
            app: .importedFile,
            title: "Imported title",
            linkedCalendarEvent: MeetingCalendarEventSnapshot(
                eventIdentifier: "calendar-2",
                title: "Calendar fallback",
                startDate: Date(),
                endDate: Date().addingTimeInterval(3_600),
                attendees: [],
            ),
            startTime: Date(),
        )
        try await meetingRepo.saveMeeting(meeting)

        let transcription = TranscriptionEntity(
            meeting: meeting,
            config: .init(text: "Imported transcript", rawText: "Imported transcript"),
        )

        try await transcriptionRepo.saveTranscription(transcription)

        let fetched = try await transcriptionRepo.fetchTranscription(by: transcription.id)
        let metadata = try await transcriptionRepo.fetchAllMetadata()

        XCTAssertNil(fetched?.meeting.title)
        XCTAssertNil(fetched?.meeting.linkedCalendarEvent)
        XCTAssertNil(fetched?.meeting.preferredTitle)
        XCTAssertNil(metadata.first?.meetingTitle)
    }

    func testFetchTranscriptionsForMeeting() async throws {
        // Given
        let meeting = MeetingEntity(app: .googleMeet)
        try await meetingRepo.saveMeeting(meeting)

        let config1 = TranscriptionEntity.Configuration(text: "T1", rawText: "T1")
        let config2 = TranscriptionEntity.Configuration(text: "T2", rawText: "T2")
        let t1 = TranscriptionEntity(meeting: meeting, config: config1)
        let t2 = TranscriptionEntity(meeting: meeting, config: config2)
        try await transcriptionRepo.saveTranscription(t1)
        try await transcriptionRepo.saveTranscription(t2)

        // When
        let results = try await transcriptionRepo.fetchTranscriptions(for: meeting.id)

        // Then
        XCTAssertEqual(results.count, 2)
    }

    func testSaveTranscription_RejectsInvalidCanonicalSummary() async throws {
        // Given
        let meeting = MeetingEntity(app: .googleMeet)
        try await meetingRepo.saveMeeting(meeting)

        let invalidSummary = CanonicalSummary(
            schemaVersion: 0,
            title: "",
            summary: "",
            trustFlags: .init(confidenceScore: 1.2),
        )

        var config = TranscriptionEntity.Configuration(text: "Raw text", rawText: "Raw text")
        config.canonicalSummary = invalidSummary
        let transcription = TranscriptionEntity(meeting: meeting, config: config)

        // When / Then
        do {
            try await transcriptionRepo.saveTranscription(transcription)
            XCTFail("Expected validation error for canonical summary payload")
        } catch let error as CanonicalSummaryValidationError {
            XCTAssertEqual(error, .unsupportedSchemaVersion(0))
        }
    }

    private func makeAttempt(
        transcriptionID: UUID,
        providerID: String,
        modelID: String,
        startedAt: Date,
        executionProvenance: ExecutionProvenance? = nil,
    ) -> ModelPerformanceAttempt {
        ModelPerformanceAttempt(
            transcriptionID: transcriptionID,
            stage: .transcription,
            attemptKind: .retry,
            capturePurpose: .dictation,
            modelIdentity: ModelPerformanceModelIdentity(
                providerID: providerID,
                providerDisplayName: providerID,
                modelID: modelID,
                modelDisplayName: modelID,
                runtimeKind: .local,
            ),
            status: .succeeded,
            startedAt: startedAt,
            completedAt: startedAt.addingTimeInterval(5),
            wallClockSeconds: 5,
            audioSeconds: 60,
            inputUTF8Bytes: 0,
            inputCharacterCount: 0,
            outputCharacterCount: 100,
            executionProvenance: executionProvenance,
        )
    }
}

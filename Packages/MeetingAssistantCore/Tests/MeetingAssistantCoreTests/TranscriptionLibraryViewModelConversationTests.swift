@testable import MeetingAssistantCore
import XCTest

@MainActor
extension TranscriptionLibraryViewModelTests {
    func testSubmitQuestionStoresGroundedAnswer() async {
        let transcription = CaptureArtifact(
            meeting: CaptureSession(id: UUID(), app: .googleMeet, startTime: Date(), endTime: Date().addingTimeInterval(60)),
            segments: [.init(speaker: "Ana", text: "Vamos lançar sexta.", startTime: 12, endTime: 16)],
            text: "Vamos lançar sexta.",
            rawText: "vamos lancar sexta",
        )

        viewModel.qaQuestion = "When are we launching?"
        meetingQAService.nextResponse = MeetingQAResponse(
            status: .answered,
            answer: "The team plans to launch on Friday.",
            evidence: [
                MeetingQAEvidence(
                    speaker: "Ana",
                    startTime: 12,
                    endTime: 16,
                    excerpt: "Vamos lançar sexta.",
                ),
            ],
        )

        await viewModel.submitQuestion(for: transcription)

        XCTAssertEqual(meetingQAService.askCallCount, 1)
        XCTAssertEqual(viewModel.qaResponse?.status, .answered)
        XCTAssertEqual(viewModel.qaResponse?.evidence.count, 1)
        XCTAssertNil(viewModel.qaErrorMessage)
    }

    func testSubmitQuestionWithEmptyInputSetsValidationError() async {
        let transcription = CaptureArtifact(
            meeting: CaptureSession(id: UUID(), app: .googleMeet, startTime: Date(), endTime: Date().addingTimeInterval(60)),
            text: "Resumo",
            rawText: "Resumo",
        )

        viewModel.qaQuestion = "   "

        await viewModel.submitQuestion(for: transcription)

        XCTAssertEqual(meetingQAService.askCallCount, 0)
        XCTAssertEqual(viewModel.qaErrorMessage, "transcription.qa.error.empty_question".localized)
    }

    func testSubmitQuestionForDictationSetsDisabledErrorAndSkipsService() async {
        let transcription = CaptureArtifact(
            meeting: CaptureSession(id: UUID(), app: .unknown, startTime: Date(), endTime: Date().addingTimeInterval(60)),
            text: "Resumo",
            rawText: "Resumo",
        )

        viewModel.qaQuestion = "What did we decide?"
        await viewModel.submitQuestion(for: transcription)

        XCTAssertEqual(meetingQAService.askCallCount, 0)
        XCTAssertEqual(viewModel.qaErrorMessage, "transcription.qa.error.disabled".localized)
    }

    func testSubmitQuestionForMeetingCaptureWithUnknownAppCallsService() async {
        let transcription = CaptureArtifact(
            meeting: CaptureSession(
                id: UUID(),
                app: .unknown,
                capturePurpose: .meeting,
                startTime: Date(),
                endTime: Date().addingTimeInterval(60),
            ),
            text: "Resumo",
            rawText: "Resumo",
        )

        viewModel.qaQuestion = "What did we decide?"
        meetingQAService.nextResponse = MeetingQAResponse(
            status: .answered,
            answer: "Action items captured.",
            evidence: [],
        )

        await viewModel.submitQuestion(for: transcription)

        XCTAssertEqual(meetingQAService.askCallCount, 1)
        XCTAssertEqual(viewModel.qaResponse?.status, .answered)
        XCTAssertNil(viewModel.qaErrorMessage)
    }

    func testRetryQuestionWithTurnID_ReusesExistingFailedTurnInPlace() async throws {
        let id = UUID()
        let transcription = CaptureArtifact(
            id: id,
            meeting: CaptureSession(id: id, app: .zoom, startTime: Date(), endTime: Date().addingTimeInterval(60)),
            text: "Summary",
            rawText: "Summary",
        )
        storage.mockTranscriptions = [transcription]
        viewModel.selectedTranscription = transcription
        viewModel.qaQuestion = "What was decided?"
        meetingQAService.nextError = .timeout

        await viewModel.submitQuestion(for: transcription)

        let failedTurn = try XCTUnwrap(viewModel.qaHistory(for: id).first)
        let originalTurnID = failedTurn.id
        let originalCreatedAt = failedTurn.createdAt
        XCTAssertEqual(viewModel.qaHistory(for: id).count, 1)
        XCTAssertNotNil(failedTurn.errorMessage)
        XCTAssertNil(failedTurn.response)

        meetingQAService.nextError = nil
        meetingQAService.nextResponse = MeetingQAResponse(
            status: .answered,
            answer: "Decision captured.",
            evidence: [.init(speaker: "A", startTime: 0, endTime: 1, excerpt: "Decision captured.")],
        )

        await viewModel.retryQuestion(failedTurn.question, turnID: failedTurn.id, for: transcription)

        let history = viewModel.qaHistory(for: id)
        XCTAssertEqual(history.count, 1)
        let updatedTurn = try XCTUnwrap(history.first)
        XCTAssertEqual(updatedTurn.id, originalTurnID)
        XCTAssertEqual(updatedTurn.createdAt, originalCreatedAt)
        XCTAssertNil(updatedTurn.errorMessage)
        XCTAssertEqual(updatedTurn.response?.answer, "Decision captured.")
    }

    func testRetryQuestionWithTurnID_PersistsUpdatedTurnWithoutGrowingConversationHistory() async throws {
        let id = UUID()
        let transcription = CaptureArtifact(
            id: id,
            meeting: CaptureSession(id: id, app: .zoom, startTime: Date(), endTime: Date().addingTimeInterval(60)),
            text: "Summary",
            rawText: "Summary",
        )
        storage.mockTranscriptions = [transcription]
        viewModel.selectedTranscription = transcription
        viewModel.qaQuestion = "Question 1"
        meetingQAService.nextError = .networkUnavailable

        await viewModel.submitQuestion(for: transcription)
        let failedTurn = try XCTUnwrap(viewModel.qaHistory(for: id).first)

        meetingQAService.nextError = .invalidResponse
        await viewModel.retryQuestion(failedTurn.question, turnID: failedTurn.id, for: transcription)

        let persistedState = try XCTUnwrap(storage.savedTranscriptions.last?.meetingConversationState)
        XCTAssertEqual(persistedState.turns.count, 1)
        XCTAssertEqual(persistedState.turns.first?.id, failedTurn.id)
        XCTAssertEqual(persistedState.turns.first?.question, failedTurn.question)
        XCTAssertNotNil(persistedState.turns.first?.errorMessage)
        XCTAssertNil(persistedState.turns.first?.response)
    }

    func testSubmitQuestion_AppendsHistoryForCurrentTranscription() async {
        let transcription = CaptureArtifact(
            meeting: CaptureSession(id: UUID(), app: .googleMeet, startTime: Date(), endTime: Date().addingTimeInterval(60)),
            text: "Summary",
            rawText: "Summary",
        )
        meetingQAService.nextResponse = MeetingQAResponse(
            status: .answered,
            answer: "Captured.",
            evidence: [.init(speaker: "A", startTime: 0, endTime: 1, excerpt: "Captured.")],
        )
        viewModel.qaQuestion = "Question 1"

        await viewModel.submitQuestion(for: transcription)

        let history = viewModel.qaHistory(for: transcription.id)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.question, "Question 1")
        XCTAssertEqual(history.first?.response?.answer, "Captured.")
    }

    func testLoadingDifferentTranscriptionResetsQuestionComposer() async {
        let id1 = UUID()
        let id2 = UUID()
        storage.mockTranscriptions = [
            CaptureArtifact(
                id: id1,
                meeting: CaptureSession(id: id1, app: .zoom, startTime: Date(), endTime: Date().addingTimeInterval(60)),
                text: "One",
                rawText: "One",
            ),
            CaptureArtifact(
                id: id2,
                meeting: CaptureSession(id: id2, app: .zoom, startTime: Date(), endTime: Date().addingTimeInterval(60)),
                text: "Two",
                rawText: "Two",
            ),
        ]
        await viewModel.loadTranscriptions()

        viewModel.qaQuestion = "Question"
        viewModel.selectedId = id1
        await waitUntil { self.viewModel.selectedTranscription?.id == id1 }
        viewModel.selectedId = id2
        await waitUntil { self.viewModel.selectedTranscription?.id == id2 }

        XCTAssertEqual(viewModel.qaQuestion, "")
    }

    func testLoadFullTranscriptionRestoresPersistedConversationState() async {
        let id = UUID()
        let transcription = CaptureArtifact(
            id: id,
            meeting: CaptureSession(id: id, app: .zoom, startTime: Date(), endTime: Date().addingTimeInterval(60)),
            text: "Meeting summary",
            rawText: "Meeting summary",
            meetingConversationState: MeetingConversationState(
                turns: [
                    MeetingConversationTurn(
                        id: UUID(),
                        question: "What was decided?",
                        response: MeetingQAResponse(
                            status: .answered,
                            answer: "Ship on Friday.",
                            evidence: [.init(speaker: "Ana", startTime: 1, endTime: 3, excerpt: "Ship Friday.")],
                        ),
                        errorMessage: nil,
                        createdAt: Date(),
                    ),
                ],
                modelSelection: MeetingQAModelSelection(
                    providerRawValue: LLMProvider.anthropic.rawValue,
                    modelID: "claude-3-7-sonnet",
                ),
            ),
        )
        storage.mockTranscriptions = [transcription]

        await viewModel.loadTranscriptions()
        viewModel.selectedId = id
        await waitUntil(message: "Persisted conversation state should restore after selection.") {
            self.viewModel.selectedTranscription?.id == id
        }

        XCTAssertEqual(viewModel.qaHistory(for: id).count, 1)
        XCTAssertEqual(viewModel.qaHistory(for: id).first?.question, "What was decided?")
        XCTAssertEqual(viewModel.qaModelSelectionByTranscription[id]?.providerRawValue, LLMProvider.anthropic.rawValue)
        XCTAssertEqual(viewModel.qaModelSelectionByTranscription[id]?.modelID, "claude-3-7-sonnet")
    }

    func testSubmitQuestionPersistsConversationState() async {
        let id = UUID()
        let transcription = CaptureArtifact(
            id: id,
            meeting: CaptureSession(id: id, app: .zoom, startTime: Date(), endTime: Date().addingTimeInterval(60)),
            text: "Summary",
            rawText: "Summary",
        )
        storage.mockTranscriptions = [transcription]
        viewModel.selectedTranscription = transcription
        meetingQAService.nextResponse = MeetingQAResponse(
            status: .answered,
            answer: "Captured.",
            evidence: [.init(speaker: "A", startTime: 0, endTime: 1, excerpt: "Captured.")],
        )
        viewModel.qaQuestion = "Question 1"

        await viewModel.submitQuestion(for: transcription)

        XCTAssertEqual(storage.savedTranscriptions.last?.id, id)
        XCTAssertEqual(storage.savedTranscriptions.last?.meetingConversationState?.turns.count, 1)
        XCTAssertEqual(storage.savedTranscriptions.last?.meetingConversationState?.turns.first?.question, "Question 1")
    }

    func testSubmitQuestionUsesConversationModelOverride() async {
        let id = UUID()
        let transcription = CaptureArtifact(
            id: id,
            meeting: CaptureSession(id: id, app: .zoom, startTime: Date(), endTime: Date().addingTimeInterval(60)),
            text: "Summary",
            rawText: "Summary",
        )
        storage.mockTranscriptions = [transcription]
        viewModel.selectedTranscription = transcription
        await viewModel.updateMeetingQAModelSelection(
            provider: .anthropic,
            model: "claude-3-7-sonnet",
            for: id,
        )
        viewModel.qaQuestion = "Question 1"

        await viewModel.submitQuestion(for: transcription)

        XCTAssertEqual(meetingQAService.lastRequest?.modelSelectionOverride?.providerRawValue, LLMProvider.anthropic.rawValue)
        XCTAssertEqual(meetingQAService.lastRequest?.modelSelectionOverride?.modelID, "claude-3-7-sonnet")
    }

    func testUpdatingChatModelSelectionDoesNotMutateEnhancementsDefaults() async {
        let settings = AppSettingsStore.shared
        let originalSelection = settings.enhancementsAISelection
        defer {
            settings.enhancementsAISelection = originalSelection
        }

        let id = UUID()
        let transcription = CaptureArtifact(
            id: id,
            meeting: CaptureSession(id: id, app: .zoom, startTime: Date(), endTime: Date().addingTimeInterval(60)),
            text: "Summary",
            rawText: "Summary",
        )
        storage.mockTranscriptions = [transcription]
        viewModel.selectedTranscription = transcription

        await viewModel.updateMeetingQAModelSelection(
            provider: .anthropic,
            model: "claude-3-7-sonnet",
            for: id,
        )

        XCTAssertEqual(settings.enhancementsAISelection, originalSelection)
        XCTAssertEqual(viewModel.qaModelSelectionByTranscription[id]?.providerRawValue, LLMProvider.anthropic.rawValue)
        XCTAssertEqual(viewModel.qaModelSelectionByTranscription[id]?.modelID, "claude-3-7-sonnet")
    }

    // MARK: - Delete Confirmation Tests

    func testConfirmDeleteTranscriptionOnlyStagesDeletion() {
        let metadata = makeMetadata(appName: "Test", appRawValue: "test", previewText: "test")
        viewModel.confirmDeleteTranscription(metadata)

        XCTAssertTrue(viewModel.showDeleteConfirmation)
        XCTAssertEqual(viewModel.pendingDeleteTranscription?.id, metadata.id)
    }

    func testCancelDeleteTranscriptionClearsConfirmationStateWithoutDeleting() {
        let metadata = makeMetadata(appName: "Test", appRawValue: "test", previewText: "test")
        viewModel.confirmDeleteTranscription(metadata)
        viewModel.cancelDeleteTranscription()

        XCTAssertFalse(viewModel.showDeleteConfirmation)
        XCTAssertNil(viewModel.pendingDeleteTranscription)
    }

    func testExecuteDeleteTranscriptionDeletesItemAndClearsState() async {
        let id = UUID()
        let transcription = CaptureArtifact(id: id, meeting: CaptureSession(id: id, app: .zoom), text: "Test", rawText: "Test")
        storage.mockTranscriptions = [transcription]
        await viewModel.loadTranscriptions()

        let metadata = makeMetadata(appName: "Test", appRawValue: "test", previewText: "test")
        let metadataWithId = TranscriptionMetadata(
            id: id,
            meetingId: id,
            appName: metadata.appName,
            appRawValue: metadata.appRawValue,
            appBundleIdentifier: nil,
            startTime: metadata.startTime,
            createdAt: metadata.createdAt,
            previewText: metadata.previewText,
            wordCount: 1,
            language: "en",
            isPostProcessed: false,
            duration: 1,
            audioFilePath: nil,
            inputSource: "test",
        )
        viewModel.confirmDeleteTranscription(metadataWithId)

        await viewModel.executeDeleteTranscription()

        XCTAssertFalse(viewModel.showDeleteConfirmation)
        XCTAssertNil(viewModel.pendingDeleteTranscription)
        XCTAssertTrue(storage.mockTranscriptions.isEmpty)
    }

    // MARK: - Manual Export Tests

    func testExportSummaryWritesProcessedContentWhenPanelReturnsURL() async throws {
        let id = UUID()
        let transcription = CaptureArtifact(
            id: id,
            meeting: CaptureSession(id: id, app: .zoom),
            text: "Processed Export Content",
            rawText: "Original Export Content",
            processedContent: "Processed Export Content",
        )
        storage.mockTranscriptions = [transcription]
        await viewModel.loadTranscriptions()

        let metadata = try XCTUnwrap(viewModel.transcriptions.first)
        let destinationURL = URL(fileURLWithPath: "/tmp/mock_export.md")

        mockSavePanel.mockRunModalResponse = .OK
        mockSavePanel.mockURL = destinationURL

        await viewModel.exportTranscription(for: metadata, kind: .summary)

        XCTAssertTrue(mockSummaryExportHelper.exportContentManuallyCalled)
        XCTAssertEqual(mockSummaryExportHelper.exportContentManuallyDestination, destinationURL)
        XCTAssertEqual(mockSummaryExportHelper.exportedContent, "Processed Export Content")
        XCTAssertNil(viewModel.operationErrorMessage)
    }

    func testExportOriginalWritesRawTextWhenPanelReturnsURL() async throws {
        let id = UUID()
        let transcription = CaptureArtifact(
            meeting: CaptureSession(id: id, app: .zoom),
            text: "Processed Export Content",
            rawText: "Original Export Content",
            processedContent: "Processed Export Content",
        )
        storage.mockTranscriptions = [transcription]
        await viewModel.loadTranscriptions()

        let metadata = try XCTUnwrap(viewModel.transcriptions.first)
        let destinationURL = URL(fileURLWithPath: "/tmp/mock_original_export.md")
        mockSavePanel.mockRunModalResponse = .OK
        mockSavePanel.mockURL = destinationURL

        await viewModel.exportTranscription(for: metadata, kind: .original)

        XCTAssertTrue(mockSummaryExportHelper.exportContentManuallyCalled)
        XCTAssertEqual(mockSummaryExportHelper.exportContentManuallyDestination, destinationURL)
        XCTAssertEqual(mockSummaryExportHelper.exportedContent, "Original Export Content")
        XCTAssertNil(viewModel.operationErrorMessage)
    }

    func testExportTranscriptionDoesNothingOnPanelCancel() async throws {
        let id = UUID()
        let transcription = CaptureArtifact(meeting: CaptureSession(id: id, app: .zoom), text: "Export Content", rawText: "Export Content")
        storage.mockTranscriptions = [transcription]
        await viewModel.loadTranscriptions()

        let metadata = try XCTUnwrap(viewModel.transcriptions.first)
        mockSavePanel.mockRunModalResponse = .cancel
        mockSavePanel.mockURL = nil

        await viewModel.exportTranscription(for: metadata, kind: .summary)

        XCTAssertFalse(mockSummaryExportHelper.exportContentManuallyCalled)
        XCTAssertNil(viewModel.operationErrorMessage)
    }

    func testExportTranscriptionSurfacesOperationalErrorWithoutTouchingLoadErrorState() async throws {
        let id = UUID()
        let transcription = CaptureArtifact(meeting: CaptureSession(id: id, app: .zoom), text: "Export Content", rawText: "Export Content")
        storage.mockTranscriptions = [transcription]
        await viewModel.loadTranscriptions()

        let metadata = try XCTUnwrap(viewModel.transcriptions.first)
        let destinationURL = URL(fileURLWithPath: "/tmp/mock_export.md")

        mockSavePanel.mockRunModalResponse = .OK
        mockSavePanel.mockURL = destinationURL

        mockSummaryExportHelper.errorToThrow = NSError(
            domain: "SummaryExportHelper",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Export failed."],
        )

        await viewModel.exportTranscription(for: metadata, kind: .summary)

        XCTAssertTrue(mockSummaryExportHelper.exportContentManuallyCalled)
        XCTAssertEqual(viewModel.operationErrorMessage, "Export failed.")
        XCTAssertNil(viewModel.loadErrorMessage)
    }
}

import Combine
@testable import MeetingAssistantCore
import XCTest

@MainActor
final class TranscriptionLibraryViewModelTests: XCTestCase {
    var viewModel: TranscriptionLibraryViewModel!
    var storage: MockStorageService!
    var meetingRepository: MockMeetingRepository!
    var meetingQAService: MockMeetingQAService!
    var cancellables: Set<AnyCancellable>!
    var mockSavePanel: MockSavePanel!
    var mockSummaryExportHelper: MockSummaryExportHelper!
    var mockKeychain: TestTranscriptionKeychainProvider!
    var readyLocalModels: Set<LocalTranscriptionModel>!

    override func setUp() async throws {
        storage = MockStorageService()
        meetingRepository = MockMeetingRepository()
        meetingQAService = MockMeetingQAService()
        mockSavePanel = MockSavePanel()
        mockSummaryExportHelper = MockSummaryExportHelper()
        mockKeychain = TestTranscriptionKeychainProvider()
        readyLocalModels = []
        viewModel = TranscriptionLibraryViewModel(
            storage: storage,
            meetingRepository: meetingRepository,
            meetingQAService: meetingQAService,
            keychain: mockKeychain,
            isLocalModelReady: { [weak self] model in
                self?.readyLocalModels.contains(model) == true
            },
            savePanelProvider: { [weak self] in self?.mockSavePanel ?? NSSavePanel() },
            summaryExportHelper: mockSummaryExportHelper,
        )
        cancellables = []
    }

    override func tearDown() async throws {
        storage = nil
        meetingRepository = nil
        meetingQAService = nil
        mockSavePanel = nil
        mockSummaryExportHelper = nil
        mockKeychain = nil
        readyLocalModels = nil
        viewModel = nil
        cancellables = nil
    }

}

final class TestTranscriptionKeychainProvider: KeychainProvider, @unchecked Sendable {
    var readyProviders = Set<TranscriptionProvider>()

    func store(_: String, for _: KeychainManager.Key) throws {}
    func retrieve(for _: KeychainManager.Key) throws -> String? {
        nil
    }

    func delete(for _: KeychainManager.Key) throws {}
    func exists(for _: KeychainManager.Key) -> Bool {
        false
    }

    func retrieveAPIKey(for _: AIProvider) throws -> String? {
        nil
    }

    func retrieveAPIKeys(for _: [AIProvider]) throws -> [AIProvider: String] {
        [:]
    }

    func existsAPIKey(for _: AIProvider) -> Bool {
        false
    }

    func storeAPIKey(_: String, for _: UUID) throws {}
    func retrieveAPIKey(for _: UUID) throws -> String? {
        nil
    }

    func retrieveAPIKeys(for _: [UUID]) throws -> [UUID: String] {
        [:]
    }

    func existsAPIKey(for _: UUID) -> Bool {
        false
    }

    func deleteAPIKey(for _: UUID) throws {}
    func storeTranscriptionAPIKey(_: String, for provider: TranscriptionProvider) throws {
        readyProviders.insert(provider)
    }

    func retrieveTranscriptionAPIKey(for _: TranscriptionProvider) throws -> String? {
        nil
    }

    func existsTranscriptionAPIKey(for provider: TranscriptionProvider) -> Bool {
        readyProviders.contains(provider)
    }

    func deleteTranscriptionAPIKey(for provider: TranscriptionProvider) throws {
        readyProviders.remove(provider)
    }
}

extension TranscriptionLibraryViewModelTests {

    func testLoadTranscriptions() async {
        // Given
        let mockId1 = UUID()
        let mockId2 = UUID()
        storage.mockTranscriptions = [
            Transcription(
                id: mockId1,
                meeting: Meeting(id: mockId1, app: .microsoftTeams, startTime: Date(), endTime: Date().addingTimeInterval(60)),
                segments: [],
                text: "Text 1",
                rawText: "Text 1",
            ),
            Transcription(
                id: mockId2,
                meeting: Meeting(id: mockId2, app: .zoom, startTime: Date(), endTime: Date().addingTimeInterval(120)),
                segments: [],
                text: "Text 2",
                rawText: "Text 2",
            ),
        ]

        // When
        await viewModel.loadTranscriptions()

        // Then
        XCTAssertEqual(viewModel.transcriptions.count, 2)
        let metadataById = Dictionary(uniqueKeysWithValues: viewModel.transcriptions.map { ($0.id, $0) })
        let teamsMetadata = metadataById[mockId1]
        let zoomMetadata = metadataById[mockId2]

        XCTAssertNotNil(teamsMetadata)
        XCTAssertNotNil(zoomMetadata)
        XCTAssertEqual(teamsMetadata?.appRawValue, MeetingApp.microsoftTeams.rawValue)
        XCTAssertEqual(teamsMetadata?.duration ?? 0, 60, accuracy: 0.1)
        XCTAssertEqual(zoomMetadata?.appRawValue, MeetingApp.zoom.rawValue)
        XCTAssertEqual(zoomMetadata?.duration ?? 0, 120, accuracy: 0.1)
        XCTAssertEqual(storage.loadAllMetadataCallCount, 0)
        XCTAssertEqual(storage.loadMetadataCallCount, 1)
        XCTAssertEqual(storage.metadataQueries.last?.limit, 250)
    }

    func testLoadTranscriptions_IncludesFailedEmptyHistoryItems() async {
        let failedId = UUID()
        storage.mockTranscriptions = [
            Transcription(
                id: failedId,
                meeting: Meeting(
                    id: failedId,
                    app: .unknown,
                    capturePurpose: .dictation,
                    startTime: Date(),
                ),
                segments: [],
                text: "",
                rawText: "",
                lifecycleState: .failed,
                postProcessingFailureReason: "Transcription failed",
            ),
        ]

        await viewModel.loadTranscriptions()

        XCTAssertEqual(viewModel.transcriptions.count, 1)
        XCTAssertEqual(viewModel.transcriptions.first?.id, failedId)
        XCTAssertEqual(viewModel.transcriptions.first?.lifecycleState, .failed)
        XCTAssertEqual(storage.loadMetadataCallCount, 1)
    }

    func testSelectTranscriptionLoadsFullData() async {
        // Given
        let mockId = UUID()
        let fullTranscription = Transcription(
            id: mockId,
            meeting: Meeting(id: mockId, app: .microsoftTeams, startTime: Date(), endTime: Date()),
            segments: [Transcription.Segment(id: UUID(), speaker: "A", text: "Hello", startTime: 0, endTime: 5)],
            text: "Hello",
            rawText: "Hello",
        )
        storage.mockTranscriptions = [fullTranscription]
        await viewModel.loadTranscriptions()

        // When
        viewModel.selectedId = mockId

        await waitUntil(message: "Selected transcription should load full detail.") {
            self.viewModel.selectedTranscription?.id == mockId
        }

        // Then
        XCTAssertNotNil(viewModel.selectedTranscription)
        XCTAssertEqual(viewModel.selectedTranscription?.id, mockId)
        XCTAssertEqual(viewModel.selectedTranscription?.segments.count, 1)
    }

    func testMatchesCapturePurposeFilter() {
        // Given
        let mockId1 = UUID()
        let mockId2 = UUID()
        let metadata1 = TranscriptionMetadata(
            id: mockId1,
            meetingId: mockId1,
            appName: "Dictation",
            appRawValue: MeetingApp.unknown.rawValue,
            appBundleIdentifier: nil,
            startTime: Date(),
            createdAt: Date(),
            previewText: "",
            wordCount: 0,
            language: "en",
            isPostProcessed: false,
            duration: 60,
            audioFilePath: nil,
            inputSource: "Microphone",
        )
        let metadata2 = TranscriptionMetadata(
            id: mockId2,
            meetingId: mockId2,
            appName: "Imported",
            appRawValue: MeetingApp.importedFile.rawValue,
            capturePurpose: .meeting,
            appBundleIdentifier: nil,
            startTime: Date(),
            createdAt: Date(),
            previewText: "",
            wordCount: 0,
            language: "en",
            isPostProcessed: false,
            duration: 120,
            audioFilePath: nil,
            inputSource: "File",
        )

        viewModel.transcriptions = [metadata1, metadata2]

        // When/Then
        // Test .all
        viewModel.capturePurposeFilter = .all
        XCTAssertEqual(viewModel.filteredTranscriptions.count, 2)

        // Test .dictations (unknown only, excluding imported files)
        viewModel.capturePurposeFilter = .dictations
        XCTAssertEqual(viewModel.filteredTranscriptions.count, 1)
        XCTAssertEqual(viewModel.filteredTranscriptions.first?.id, mockId1)

        // Test .meetings (meeting capture, including imported files)
        viewModel.capturePurposeFilter = .meetings
        XCTAssertEqual(viewModel.filteredTranscriptions.count, 1)
        XCTAssertEqual(viewModel.filteredTranscriptions.first?.id, mockId2)

        // Imported files remain visible under .all
        viewModel.capturePurposeFilter = .all
        XCTAssertEqual(viewModel.filteredTranscriptions.count, 2)
        XCTAssertTrue(viewModel.filteredTranscriptions.contains(where: { $0.id == mockId2 }))
    }

    func testAppFilterOptionsIncludesAllAndLoadedApps() {
        // Given
        let metadata1 = makeMetadata(
            appName: "Zoom",
            appRawValue: MeetingApp.zoom.rawValue,
            previewText: "Sprint planning",
        )
        let metadata2 = makeMetadata(
            appName: "Microsoft Teams",
            appRawValue: MeetingApp.microsoftTeams.rawValue,
            previewText: "Roadmap review",
        )
        viewModel.transcriptions = [metadata1, metadata2]

        // When
        let options = viewModel.appFilterOptions

        // Then
        XCTAssertEqual(options.first?.id, "__all_apps__")
        XCTAssertTrue(options.contains(where: { $0.id == "raw:\(MeetingApp.zoom.rawValue)" }))
        XCTAssertTrue(options.contains(where: { $0.id == "raw:\(MeetingApp.microsoftTeams.rawValue)" }))
    }

    func testFilteredTranscriptionsAppliesAppAndSearchFilters() {
        // Given
        let zoomMetadata = makeMetadata(
            appName: "Zoom",
            appRawValue: MeetingApp.zoom.rawValue,
            previewText: "Discussed quarterly results",
        )
        let teamsMetadata = makeMetadata(
            appName: "Microsoft Teams",
            appRawValue: MeetingApp.microsoftTeams.rawValue,
            previewText: "Reunião de planejamento",
        )
        viewModel.transcriptions = [zoomMetadata, teamsMetadata]

        // When
        viewModel.appFilterId = "raw:\(MeetingApp.microsoftTeams.rawValue)"
        viewModel.searchText = "reuniao"

        // Then
        XCTAssertEqual(viewModel.filteredTranscriptions.count, 1)
        XCTAssertEqual(viewModel.filteredTranscriptions.first?.id, teamsMetadata.id)
    }

    func testFilterChangesDoNotTriggerAdditionalStorageLoads() async {
        let now = Date()
        let meetingID = UUID()
        let dictationID = UUID()
        storage.mockTranscriptions = [
            Transcription(
                id: meetingID,
                meeting: Meeting(
                    id: meetingID,
                    app: .zoom,
                    capturePurpose: .meeting,
                    startTime: now,
                    endTime: now.addingTimeInterval(60),
                ),
                segments: [],
                text: "Quarterly review",
                rawText: "Quarterly review",
            ),
            Transcription(
                id: dictationID,
                meeting: Meeting(
                    id: dictationID,
                    app: .unknown,
                    capturePurpose: .dictation,
                    startTime: now,
                    endTime: now.addingTimeInterval(30),
                ),
                segments: [],
                text: "Quick dictation",
                rawText: "Quick dictation",
            ),
        ]

        await viewModel.loadTranscriptions()

        viewModel.capturePurposeFilter = .dictations
        viewModel.searchText = "quick"
        viewModel.dateFilter = .allEntries

        XCTAssertEqual(viewModel.filteredTranscriptions.count, 1)
        XCTAssertEqual(storage.loadAllMetadataCallCount, 0)
        XCTAssertEqual(storage.loadMetadataCallCount, 1)
        XCTAssertEqual(storage.metadataQueries.last?.capturePurposeFilter, .all)
        XCTAssertEqual(storage.metadataQueries.last?.dateFilter, .allEntries)
        XCTAssertEqual(storage.metadataQueries.last?.searchText, "")
    }

    func testLoadTranscriptions_UsesRawAppFilterInMetadataQuery() async {
        let zoom = Transcription(
            id: UUID(),
            meeting: Meeting(id: UUID(), app: .zoom, startTime: Date()),
            segments: [],
            text: "Zoom notes",
            rawText: "Zoom notes",
        )
        let teams = Transcription(
            id: UUID(),
            meeting: Meeting(id: UUID(), app: .microsoftTeams, startTime: Date()),
            segments: [],
            text: "Teams notes",
            rawText: "Teams notes",
        )
        storage.mockTranscriptions = [zoom, teams]
        viewModel.appFilterId = "raw:\(MeetingApp.zoom.rawValue)"

        await viewModel.loadTranscriptions()

        XCTAssertEqual(viewModel.transcriptions.map(\.id), [zoom.id])
        XCTAssertEqual(storage.loadMetadataCallCount, 1)
        XCTAssertEqual(storage.loadAllMetadataCallCount, 0)
        XCTAssertEqual(storage.metadataQueries.last?.appRawValue, MeetingApp.zoom.rawValue)
    }

    func testLoadTranscriptions_UsesUnboundedFallbackForBundleAppFilter() async {
        let transcription = Transcription(
            id: UUID(),
            meeting: Meeting(
                id: UUID(),
                app: .zoom,
                appBundleIdentifier: "com.example.zoom",
                startTime: Date(),
            ),
            segments: [],
            text: "Zoom notes",
            rawText: "Zoom notes",
        )
        storage.mockTranscriptions = [transcription]
        viewModel.appFilterId = "bundle:com.example.zoom"

        await viewModel.loadTranscriptions()

        XCTAssertEqual(viewModel.transcriptions.map(\.id), [transcription.id])
        XCTAssertEqual(storage.loadAllMetadataCallCount, 1)
        XCTAssertEqual(storage.loadMetadataCallCount, 0)
    }

    func testFilteredTranscriptions_SearchMatchesMeetingTitleOnlyForMeetings() {
        let meetingMetadata = makeMetadata(
            appName: "Zoom",
            appRawValue: MeetingApp.zoom.rawValue,
            previewText: "General discussion",
            meetingTitle: "Quarterly Planning",
        )
        let dictationMetadata = makeMetadata(
            appName: "Codex",
            appRawValue: MeetingApp.unknown.rawValue,
            previewText: "General discussion",
            meetingTitle: "Should not match",
        )
        viewModel.transcriptions = [meetingMetadata, dictationMetadata]

        viewModel.searchText = "quarterly"

        XCTAssertEqual(viewModel.filteredTranscriptions.count, 1)
        XCTAssertEqual(viewModel.filteredTranscriptions.first?.id, meetingMetadata.id)
    }

    func testAvailableRetryTranscriptionOptions_MeetingIncludesOnlyInstalledLocalModels() {
        let metadata = makeMetadata(
            appName: "Zoom",
            appRawValue: MeetingApp.zoom.rawValue,
            previewText: "Meeting text",
            capturePurpose: .meeting,
        )
        let installedModel = LocalTranscriptionModel.parakeetTdt06BV3
        readyLocalModels = [installedModel]

        let options = viewModel.availableRetryTranscriptionOptions(for: metadata)

        XCTAssertEqual(options.map(\.selection.provider), [.local])
        XCTAssertEqual(options.map(\.selection.selectedModel), [installedModel.rawValue])
    }

    func testAvailableRetryTranscriptionOptions_DictationIncludesInstalledLocalAndReadyRemoteProviders() {
        let metadata = makeMetadata(
            appName: "Prisma",
            appRawValue: MeetingApp.unknown.rawValue,
            previewText: "Dictation text",
            capturePurpose: .dictation,
        )
        let installedModel = LocalTranscriptionModel.parakeetTdt06BV3
        readyLocalModels = [installedModel]
        mockKeychain.readyProviders = [.groq]

        let options = viewModel.availableRetryTranscriptionOptions(for: metadata)

        XCTAssertEqual(options.first?.selection.provider, .local)
        XCTAssertEqual(options.first?.selection.selectedModel, installedModel.rawValue)
        XCTAssertEqual(
            Array(options.dropFirst().map(\.selection)),
            TranscriptionProvider.groqPresetModelIDs.map {
                TranscriptionProviderSelection(provider: .groq, selectedModel: $0)
            },
        )
    }

    func testAvailableRetryTranscriptionOptions_DictationKeepsLegacyScribeV1Eligible() {
        let metadata = makeMetadata(
            appName: "Prisma",
            appRawValue: MeetingApp.unknown.rawValue,
            previewText: "Dictation text",
            capturePurpose: .dictation
        )
        readyLocalModels = []
        mockKeychain.readyProviders = [.elevenLabs]

        let options = viewModel.availableRetryTranscriptionOptions(for: metadata)

        XCTAssertEqual(
            options.map(\.selection),
            [
                TranscriptionProviderSelection(provider: .elevenLabs, selectedModel: "scribe_v1"),
                TranscriptionProviderSelection(provider: .elevenLabs, selectedModel: "scribe_v2")
            ]
        )
    }

    func testUpdateMeetingTitle_PersistsTrimmedTitleAndRefreshesSelection() async throws {
        let id = UUID()
        let originalMeeting = Meeting(
            id: id,
            app: .zoom,
            title: "Initial",
            linkedCalendarEvent: MeetingCalendarEventSnapshot(
                eventIdentifier: "event-1",
                title: "Calendar Title",
                startDate: Date(),
                endDate: Date().addingTimeInterval(60),
            ),
            startTime: Date(),
            endTime: Date().addingTimeInterval(60),
        )
        let transcription = Transcription(
            id: id,
            meeting: originalMeeting,
            text: "Summary",
            rawText: "Summary",
        )
        storage.mockTranscriptions = [transcription]
        meetingRepository.meetingsByID[id] = MeetingEntity(
            id: id,
            app: .zoom,
            appDisplayName: "Zoom",
            title: "Initial",
            linkedCalendarEvent: originalMeeting.linkedCalendarEvent,
            startTime: originalMeeting.startTime,
            endTime: originalMeeting.endTime,
            audioFilePath: originalMeeting.audioFilePath,
        )
        meetingRepository.onUpdateMeeting = { [storage] meeting in
            storage?.mockTranscriptions = storage?.mockTranscriptions.map { transcription in
                guard transcription.meeting.id == meeting.id else { return transcription }

                let updatedMeeting = Meeting(
                    id: transcription.meeting.id,
                    app: transcription.meeting.app,
                    appBundleIdentifier: transcription.meeting.appBundleIdentifier,
                    appDisplayName: transcription.meeting.appDisplayName,
                    title: meeting.title,
                    linkedCalendarEvent: meeting.linkedCalendarEvent,
                    type: transcription.meeting.type,
                    state: transcription.meeting.state,
                    startTime: transcription.meeting.startTime,
                    endTime: transcription.meeting.endTime,
                    audioFilePath: transcription.meeting.audioFilePath,
                )

                return Transcription(
                    id: transcription.id,
                    meeting: updatedMeeting,
                    contextItems: transcription.contextItems,
                    segments: transcription.segments,
                    text: transcription.text,
                    rawText: transcription.rawText,
                    processedContent: transcription.processedContent,
                    canonicalSummary: transcription.canonicalSummary,
                    qualityProfile: transcription.qualityProfile,
                    postProcessingPromptId: transcription.postProcessingPromptId,
                    postProcessingPromptTitle: transcription.postProcessingPromptTitle,
                    language: transcription.language,
                    createdAt: transcription.createdAt,
                    modelName: transcription.modelName,
                    inputSource: transcription.inputSource,
                    transcriptionDuration: transcription.transcriptionDuration,
                    postProcessingDuration: transcription.postProcessingDuration,
                    postProcessingModel: transcription.postProcessingModel,
                    meetingType: transcription.meetingType,
                    meetingConversationState: transcription.meetingConversationState,
                )
            } ?? []
        }

        await viewModel.loadTranscriptions()
        viewModel.selectedId = id
        await waitUntil(message: "Selected transcription should reflect the updated meeting title.") {
            self.viewModel.selectedTranscription?.id == id
        }

        let metadata = try XCTUnwrap(viewModel.transcriptions.first)
        await viewModel.updateMeetingTitle(for: metadata, to: "  Executive Sync  ")

        XCTAssertEqual(meetingRepository.updatedMeetings.last?.title, "Executive Sync")
        XCTAssertEqual(meetingRepository.updatedMeetings.last?.linkedCalendarEvent?.eventIdentifier, "event-1")
        XCTAssertEqual(viewModel.transcriptions.first?.meetingTitle, "Executive Sync")
        XCTAssertEqual(viewModel.selectedTranscription?.meeting.title, "Executive Sync")
    }

    func testUpdateMeetingTitle_EmptyValueClearsCustomTitle() async throws {
        let id = UUID()
        let transcription = Transcription(
            id: id,
            meeting: Meeting(id: id, app: .zoom, title: "Existing", startTime: Date(), endTime: Date().addingTimeInterval(60)),
            text: "Summary",
            rawText: "Summary",
        )
        storage.mockTranscriptions = [transcription]
        meetingRepository.meetingsByID[id] = MeetingEntity(
            id: id,
            app: .zoom,
            appDisplayName: "Zoom",
            title: "Existing",
            startTime: transcription.meeting.startTime,
            endTime: transcription.meeting.endTime,
            audioFilePath: transcription.meeting.audioFilePath,
        )
        meetingRepository.onUpdateMeeting = { [storage] meeting in
            storage?.mockTranscriptions = storage?.mockTranscriptions.map { transcription in
                guard transcription.meeting.id == meeting.id else { return transcription }
                return Transcription(
                    id: transcription.id,
                    meeting: Meeting(
                        id: transcription.meeting.id,
                        app: transcription.meeting.app,
                        appBundleIdentifier: transcription.meeting.appBundleIdentifier,
                        appDisplayName: transcription.meeting.appDisplayName,
                        title: meeting.title,
                        linkedCalendarEvent: transcription.meeting.linkedCalendarEvent,
                        type: transcription.meeting.type,
                        state: transcription.meeting.state,
                        startTime: transcription.meeting.startTime,
                        endTime: transcription.meeting.endTime,
                        audioFilePath: transcription.meeting.audioFilePath,
                    ),
                    contextItems: transcription.contextItems,
                    segments: transcription.segments,
                    text: transcription.text,
                    rawText: transcription.rawText,
                    processedContent: transcription.processedContent,
                    canonicalSummary: transcription.canonicalSummary,
                    qualityProfile: transcription.qualityProfile,
                    postProcessingPromptId: transcription.postProcessingPromptId,
                    postProcessingPromptTitle: transcription.postProcessingPromptTitle,
                    language: transcription.language,
                    createdAt: transcription.createdAt,
                    modelName: transcription.modelName,
                    inputSource: transcription.inputSource,
                    transcriptionDuration: transcription.transcriptionDuration,
                    postProcessingDuration: transcription.postProcessingDuration,
                    postProcessingModel: transcription.postProcessingModel,
                    meetingType: transcription.meetingType,
                    meetingConversationState: transcription.meetingConversationState,
                )
            } ?? []
        }

        await viewModel.loadTranscriptions()

        let metadata = try XCTUnwrap(viewModel.transcriptions.first)
        await viewModel.updateMeetingTitle(for: metadata, to: "   ")

        XCTAssertNil(meetingRepository.updatedMeetings.last?.title)
        XCTAssertNil(viewModel.transcriptions.first?.meetingTitle)
    }

    func testUpdateMeetingTitle_PreservesMeetingCapturePurposeForUnknownApp() async throws {
        let id = UUID()
        let startTime = Date()
        let transcription = Transcription(
            id: id,
            meeting: Meeting(
                id: id,
                app: .unknown,
                capturePurpose: .meeting,
                startTime: startTime,
                endTime: startTime.addingTimeInterval(60),
            ),
            text: "Summary",
            rawText: "Summary",
        )
        storage.mockTranscriptions = [transcription]
        meetingRepository.meetingsByID[id] = MeetingEntity(
            id: id,
            app: .unknown,
            capturePurpose: .meeting,
            startTime: transcription.meeting.startTime,
            endTime: transcription.meeting.endTime,
            audioFilePath: transcription.meeting.audioFilePath,
        )

        await viewModel.loadTranscriptions()
        let metadata = try XCTUnwrap(viewModel.transcriptions.first)

        await viewModel.updateMeetingTitle(for: metadata, to: " Team Sync ")

        XCTAssertEqual(meetingRepository.updatedMeetings.last?.capturePurpose, .meeting)
    }

    func testUpdateCapturePurpose_ConvertsUnknownToManualMeeting() async throws {
        let id = UUID()
        let startTime = Date()
        let transcription = Transcription(
            id: id,
            meeting: Meeting(
                id: id,
                app: .unknown,
                capturePurpose: .dictation,
                startTime: startTime,
                endTime: startTime.addingTimeInterval(120),
            ),
            text: "Summary",
            rawText: "Summary",
        )
        storage.mockTranscriptions = [transcription]
        meetingRepository.meetingsByID[id] = MeetingEntity(
            id: id,
            app: .unknown,
            capturePurpose: .dictation,
            startTime: transcription.meeting.startTime,
            endTime: transcription.meeting.endTime,
            audioFilePath: transcription.meeting.audioFilePath,
        )

        await viewModel.loadTranscriptions()
        let metadata = try XCTUnwrap(viewModel.transcriptions.first)

        await viewModel.updateCapturePurpose(for: metadata, to: .meeting)

        XCTAssertEqual(meetingRepository.updatedMeetings.last?.capturePurpose, .meeting)
        XCTAssertEqual(meetingRepository.updatedMeetings.last?.app, .manualMeeting)
    }

    func testUpdateCapturePurpose_ConvertsManualMeetingToUnknownDictation() async throws {
        let id = UUID()
        let startTime = Date()
        let transcription = Transcription(
            id: id,
            meeting: Meeting(
                id: id,
                app: .manualMeeting,
                capturePurpose: .meeting,
                startTime: startTime,
                endTime: startTime.addingTimeInterval(120),
            ),
            text: "Summary",
            rawText: "Summary",
        )
        storage.mockTranscriptions = [transcription]
        meetingRepository.meetingsByID[id] = MeetingEntity(
            id: id,
            app: .manualMeeting,
            capturePurpose: .meeting,
            startTime: transcription.meeting.startTime,
            endTime: transcription.meeting.endTime,
            audioFilePath: transcription.meeting.audioFilePath,
        )

        await viewModel.loadTranscriptions()
        let metadata = try XCTUnwrap(viewModel.transcriptions.first)

        await viewModel.updateCapturePurpose(for: metadata, to: .dictation)

        XCTAssertEqual(meetingRepository.updatedMeetings.last?.capturePurpose, .dictation)
        XCTAssertEqual(meetingRepository.updatedMeetings.last?.app, .unknown)
    }

    func testImportedMeetingSupportsConversationAndCanBeRetaggedAsDictation() async throws {
        let id = UUID()
        let startTime = Date()
        let transcription = Transcription(
            id: id,
            meeting: Meeting(
                id: id,
                app: .importedFile,
                capturePurpose: .meeting,
                title: "Imported call",
                startTime: startTime,
                endTime: startTime.addingTimeInterval(120),
            ),
            text: "Imported meeting",
            rawText: "Imported meeting",
        )
        storage.mockTranscriptions = [transcription]
        meetingRepository.meetingsByID[id] = MeetingEntity(
            id: id,
            app: .importedFile,
            capturePurpose: .meeting,
            title: "Imported call",
            startTime: startTime,
            endTime: startTime.addingTimeInterval(120),
        )

        await viewModel.loadTranscriptions()
        let metadata = try XCTUnwrap(viewModel.transcriptions.first)

        XCTAssertTrue(viewModel.canOpenMeetingConversation(for: metadata))

        await viewModel.updateCapturePurpose(for: metadata, to: .dictation)

        XCTAssertEqual(meetingRepository.updatedMeetings.last?.app, .importedFile)
        XCTAssertEqual(meetingRepository.updatedMeetings.last?.capturePurpose, .dictation)
        XCTAssertNil(meetingRepository.updatedMeetings.last?.title)
    }

    func testAppFilterOptionsIncludeUnknownAppsByDisplayName() {
        // Given
        let codexMetadata = makeMetadata(
            appName: "Codex",
            appRawValue: MeetingApp.unknown.rawValue,
            previewText: "Discussing refinements",
        )
        let browserMetadata = makeMetadata(
            appName: "Arc Browser",
            appRawValue: MeetingApp.unknown.rawValue,
            previewText: "Planning meeting",
        )
        viewModel.transcriptions = [codexMetadata, browserMetadata]

        // When
        let options = viewModel.appFilterOptions

        // Then
        XCTAssertTrue(options.contains(where: { $0.displayName == "Codex" }))
        XCTAssertTrue(options.contains(where: { $0.displayName == "Arc Browser" }))
        XCTAssertFalse(options.contains(where: { $0.displayName == MeetingApp.unknown.displayName }))
    }

    func testFilteredTranscriptionsAppliesUnknownDisplayNameAppFilter() {
        // Given
        let codexMetadata = makeMetadata(
            appName: "Codex",
            appRawValue: MeetingApp.unknown.rawValue,
            previewText: "Implemented one two three",
        )
        let browserMetadata = makeMetadata(
            appName: "Arc Browser",
            appRawValue: MeetingApp.unknown.rawValue,
            previewText: "General notes",
        )
        viewModel.transcriptions = [codexMetadata, browserMetadata]
        let codexFilterOption = viewModel.appFilterOptions.first(where: { $0.displayName == "Codex" })

        // When
        viewModel.appFilterId = codexFilterOption?.id ?? "__all_apps__"

        // Then
        XCTAssertEqual(viewModel.filteredTranscriptions.count, 1)
        XCTAssertEqual(viewModel.filteredTranscriptions.first?.id, codexMetadata.id)
    }

    func makeMetadata(
        appName: String,
        appRawValue: String,
        previewText: String,
        meetingTitle: String? = nil,
        capturePurpose: CapturePurpose? = nil,
    ) -> TranscriptionMetadata {
        let id = UUID()
        return TranscriptionMetadata(
            id: id,
            meetingId: id,
            meetingTitle: meetingTitle,
            appName: appName,
            appRawValue: appRawValue,
            capturePurpose: capturePurpose,
            appBundleIdentifier: nil,
            startTime: Date(),
            createdAt: Date(),
            previewText: previewText,
            wordCount: previewText.count,
            language: "en",
            isPostProcessed: false,
            duration: 60,
            audioFilePath: nil,
            inputSource: "Microphone",
        )
    }

}

class MockSavePanel: NSSavePanel, @unchecked Sendable {
    var mockRunModalResponse: NSApplication.ModalResponse = .cancel
    var mockURL: URL?
    override var url: URL? {
        mockURL
    }

    override func runModal() -> NSApplication.ModalResponse {
        mockRunModalResponse
    }
}

class MockSummaryExportHelper: SummaryExportHelperProtocol, @unchecked Sendable {
    var exportContentManuallyCalled = false
    var exportContentManuallyDestination: URL?
    var exportedContent: String?
    var errorToThrow: Error?

    func exportAutomatically(transcription: Transcription) async {}

    func exportContentManually(_ content: String, to destinationURL: URL) throws {
        exportContentManuallyCalled = true
        exportContentManuallyDestination = destinationURL
        exportedContent = content
        if let error = errorToThrow {
            throw error
        }
    }

    func defaultExportFilename(for transcription: Transcription) -> String {
        "mock_file"
    }
}

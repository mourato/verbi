import AppKit
import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import OSLog
import SwiftUI

@MainActor
public class TranscriptionSettingsViewModel: ObservableObject {
    public struct AppFilterOption: Identifiable, Hashable, Sendable {
        public enum Scope: Hashable, Sendable {
            case all
            case appRawValue(String)
            case appBundleIdentifier(String)
            case appDisplayName(String)
        }

        public let id: String
        public let scope: Scope
        public let displayName: String
    }

    private enum FilterConstants {
        static let allAppsId = "__all_apps__"
        static let rawAppPrefix = "raw:"
        static let bundleAppPrefix = "bundle:"
        static let nameAppPrefix = "name:"
        static let metadataLimit = 250
    }

    public struct QATurn: Identifiable, Hashable, Sendable {
        public let id: UUID
        public let question: String
        public let response: MeetingQAResponse?
        public let errorMessage: String?
        public let createdAt: Date

        public init(
            id: UUID = UUID(),
            question: String,
            response: MeetingQAResponse?,
            errorMessage: String?,
            createdAt: Date = Date()
        ) {
            self.id = id
            self.question = question
            self.response = response
            self.errorMessage = errorMessage
            self.createdAt = createdAt
        }
    }

    @Published public var transcriptions: [TranscriptionMetadata] = []
    @Published public var selectedTranscription: Transcription?
    @Published public var selectedId: UUID? {
        didSet {
            if let id = selectedId {
                Task { await self.loadFullTranscription(id: id) }
            } else {
                Task {
                    self.selectedTranscription = nil
                }
            }
        }
    }

    @Published public var isProcessingAI = false
    @Published public var postProcessingByTranscriptionID: Set<UUID> = []
    @Published public var postProcessingErrorByTranscriptionID: [UUID: String] = [:]
    @Published public var qaQuestion = ""
    @Published public var qaResponse: MeetingQAResponse?
    @Published public var isAnsweringQuestion = false
    @Published public var qaErrorMessage: String?
    @Published public var qaHistoryByTranscription: [UUID: [QATurn]] = [:]
    @Published public var qaModelSelectionByTranscription: [UUID: MeetingQAModelSelection] = [:]

    @Published public var isLoading = true
    @Published public var sourceFilter: RecordingSourceFilter = .all
    @Published public var dateFilter: DateFilter = .thisWeek
    @Published public var searchText = ""
    @Published public var appFilterId = FilterConstants.allAppsId
    @Published public var loadErrorMessage: String?
    @Published public var operationErrorMessage: String?

    @Published public var showDeleteConfirmation = false
    @Published public var pendingDeleteTranscription: TranscriptionMetadata?

    private var hasInitialLoadCompleted = false

    let storage: StorageService
    let recordingManager: RecordingManager
    let meetingRepository: MeetingRepository
    let meetingQAService: any MeetingQAServiceProtocol
    let meetingNotesRichTextStore: any MeetingNotesRichTextStoreProtocol
    let meetingNotesMarkdownStore: any MeetingNotesMarkdownDocumentStoreProtocol
    let settings: AppSettingsStore
    let keychain: KeychainProvider
    let isLocalModelReady: @MainActor (LocalTranscriptionModel) -> Bool
    let savePanelProvider: @MainActor () -> NSSavePanel
    let summaryExportHelper: SummaryExportHelperProtocol
    let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "TranscriptionSettingsViewModel")

    static let segmentSortComparator: (Transcription.Segment, Transcription.Segment) -> Bool = { lhs, rhs in
        if lhs.startTime != rhs.startTime {
            return lhs.startTime < rhs.startTime
        }
        if lhs.endTime != rhs.endTime {
            return lhs.endTime < rhs.endTime
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    public init(
        storage: StorageService = FileSystemStorageService.shared,
        recordingManager: RecordingManager = .shared,
        meetingRepository: MeetingRepository = CoreDataMeetingRepository(),
        meetingQAService: any MeetingQAServiceProtocol = MeetingQAService.shared,
        meetingNotesRichTextStore: any MeetingNotesRichTextStoreProtocol = MeetingNotesRichTextStore(),
        meetingNotesMarkdownStore: any MeetingNotesMarkdownDocumentStoreProtocol = MeetingNotesMarkdownDocumentStore.shared,
        settings: AppSettingsStore = .shared,
        keychain: KeychainProvider = DefaultKeychainProvider(),
        isLocalModelReady: @escaping @MainActor (LocalTranscriptionModel) -> Bool = {
            FluidAIModelManager.shared.isASRModelInstalled(localModelID: $0.rawValue)
        },
        savePanelProvider: @escaping @MainActor () -> NSSavePanel = { NSSavePanel() },
        summaryExportHelper: SummaryExportHelperProtocol = SummaryExportHelper()
    ) {
        self.storage = storage
        self.recordingManager = recordingManager
        self.meetingRepository = meetingRepository
        self.meetingQAService = meetingQAService
        self.meetingNotesRichTextStore = meetingNotesRichTextStore
        self.meetingNotesMarkdownStore = meetingNotesMarkdownStore
        self.settings = settings
        self.keychain = keychain
        self.isLocalModelReady = isLocalModelReady
        self.savePanelProvider = savePanelProvider
        self.summaryExportHelper = summaryExportHelper
    }

    public var isMeetingQnAEnabled: Bool {
        settings.meetingQnAEnabled
    }

    public func canOpenMeetingConversation(for metadata: TranscriptionMetadata) -> Bool {
        metadata.supportsMeetingConversation
    }

    public func qaHistory(for transcriptionID: UUID) -> [QATurn] {
        qaHistoryByTranscription[transcriptionID] ?? []
    }

    public func effectiveMeetingQAModelSelection(for transcriptionID: UUID) -> MeetingQAModelSelection {
        if let override = qaModelSelectionByTranscription[transcriptionID],
           AIProvider(rawValue: override.providerRawValue) != nil,
           !override.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return override
        }

        let defaults = settings.enhancementsAISelection
        return MeetingQAModelSelection(
            providerRawValue: defaults.provider.rawValue,
            modelID: defaults.selectedModel
        )
    }

    public var filteredTranscriptions: [TranscriptionMetadata] {
        TranscriptionHistoryFilterEngine.filteredTranscriptions(
            from: transcriptions,
            configuration: .init(
                sourceFilter: sourceFilter,
                dateFilter: dateFilter,
                searchText: searchText,
                appFilterId: appFilterId,
                allAppsId: FilterConstants.allAppsId,
                rawAppPrefix: FilterConstants.rawAppPrefix,
                bundleAppPrefix: FilterConstants.bundleAppPrefix,
                nameAppPrefix: FilterConstants.nameAppPrefix
            )
        )
    }

    public var appFilterOptions: [AppFilterOption] {
        let dateAndSourceFiltered = transcriptions.filter { transcription in
            let matchesSource = TranscriptionHistoryFilterEngine.matchesSourceFilter(transcription, sourceFilter: sourceFilter)
            let matchesDate = dateFilter.contains(transcription.createdAt)
            return matchesSource && matchesDate
        }
        return TranscriptionHistoryFilterEngine.appFilterOptions(
            from: dateAndSourceFiltered,
            allAppsId: FilterConstants.allAppsId,
            rawAppPrefix: FilterConstants.rawAppPrefix,
            bundleAppPrefix: FilterConstants.bundleAppPrefix,
            nameAppPrefix: FilterConstants.nameAppPrefix
        )
    }

    /// Transcriptions grouped by date (start of day) for section headers.
    public var groupedTranscriptions: [Date: [TranscriptionMetadata]] {
        Dictionary(grouping: filteredTranscriptions) { metadata in
            Calendar.current.startOfDay(for: metadata.createdAt)
        }
    }

    /// Sorted list of dates for the group headers.
    public var sortedGroupDates: [Date] {
        groupedTranscriptions.keys.sorted(by: >)
    }

    public func loadIfNeeded() async {
        guard !hasInitialLoadCompleted else { return }
        await loadTranscriptions()
    }

    public func loadTranscriptions() async {
        isLoading = true
        loadErrorMessage = nil
        do {
            let metadata = if appFilterId.hasPrefix(FilterConstants.bundleAppPrefix)
                || appFilterId.hasPrefix(FilterConstants.nameAppPrefix)
            {
                try await storage.loadAllMetadata()
            } else {
                try await storage.loadMetadata(matching: TranscriptionMetadataQuery(
                    sourceFilter: .all,
                    dateFilter: .allEntries,
                    searchText: "",
                    appRawValue: rawAppValueFilter,
                    limit: FilterConstants.metadataLimit
                ))
            }

            transcriptions = metadata.filter {
                $0.lifecycleState == .failed || !($0.duration == 0 && $0.previewText.isEmpty)
            }
            if !appFilterOptions.contains(where: { $0.id == appFilterId }) {
                appFilterId = FilterConstants.allAppsId
            }

            if let selectedId, !transcriptions.contains(where: { $0.id == selectedId }) {
                self.selectedId = nil
            }
        } catch {
            logger.error("Failed to load transcriptions: \(error.localizedDescription)")
            loadErrorMessage = "settings.transcriptions.error_load".localized
        }
        isLoading = false
        hasInitialLoadCompleted = true
    }

    private var rawAppValueFilter: String? {
        guard appFilterId.hasPrefix(FilterConstants.rawAppPrefix) else { return nil }
        let rawValue = String(appFilterId.dropFirst(FilterConstants.rawAppPrefix.count))
        return rawValue.isEmpty ? nil : rawValue
    }

    public func loadFullTranscription(id: UUID) async {
        do {
            if selectedTranscription?.id != id {
                resetQuestionState()
            }
            selectedTranscription = try await storage.loadTranscription(by: id)
            if let selectedTranscription {
                restoreMeetingConversationState(from: selectedTranscription)
            }
        } catch {
            logger.error("Failed to load full transcription: \(error.localizedDescription)")
        }
    }
}

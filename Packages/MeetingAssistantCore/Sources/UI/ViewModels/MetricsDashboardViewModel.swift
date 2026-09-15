import Combine
import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import OSLog

@MainActor
public final class MetricsDashboardViewModel: ObservableObject {
    @Published public private(set) var summary: MetricsDashboardSummary
    @Published public private(set) var weekdayBuckets: [MetricsWeekdayBucket] = []
    @Published public private(set) var hourlyBuckets: [MetricsHourlyBucket] = []
    @Published public private(set) var dailyBuckets: [MetricsDailyBucket] = []
    @Published public private(set) var appUsageBuckets: [MetricsAppUsageBucket] = []
    @Published public private(set) var upcomingEvents: [MeetingCalendarEventSnapshot] = []
    @Published public private(set) var calendarPermissionState: PermissionState
    @Published public private(set) var activeLinkedCalendarEventID: String?
    @Published public private(set) var isRecording = false
    @Published public private(set) var isLoadingCalendar = false
    @Published public private(set) var isMeetingTranscriptionEnabled: Bool

    @Published public var dateFilter: DateFilter = .allEntries {
        didSet {
            recompute()
        }
    }

    @Published public var showDictations: Bool = true {
        didSet {
            guard oldValue != showDictations else { return }
            recompute()
        }
    }

    @Published public var showMeetings: Bool = false {
        didSet {
            guard oldValue != showMeetings else { return }
            recompute()
        }
    }

    @Published public private(set) var isLoading = true
    @Published public private(set) var errorMessage: String?

    private let storage: StorageService
    private let calendarEventService: any CalendarEventServiceProtocol
    private let recordingManager: RecordingManager
    private let settingsStore: AppSettingsStore
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "MetricsDashboardViewModel")
    private var allMetadata: [TranscriptionMetadata] = []
    private var isRefreshing = false
    private var hasLoaded = false
    private var cancellables = Set<AnyCancellable>()

    private static let DEFAULT_BASELINE_WPM: Double = 35

    public init(
        storage: StorageService = FileSystemStorageService.shared,
        calendarEventService: any CalendarEventServiceProtocol = CalendarEventService.shared,
        recordingManager: RecordingManager = .shared,
        settingsStore: AppSettingsStore = .shared
    ) {
        self.storage = storage
        self.calendarEventService = calendarEventService
        self.recordingManager = recordingManager
        self.settingsStore = settingsStore
        isMeetingTranscriptionEnabled = settingsStore.isMeetingTranscriptionEnabled
        calendarPermissionState = calendarEventService.authorizationState()
        activeLinkedCalendarEventID = recordingManager.currentMeeting?.linkedCalendarEvent?.eventIdentifier
        isRecording = recordingManager.isRecording
        summary = MetricsAggregator.computeSummary(
            metadata: [],
            baselineTypingWordsPerMinute: Self.DEFAULT_BASELINE_WPM
        )

        bindRecordingState()

        if storage is FileSystemStorageService, let cachedMetadata = DashboardMetadataCache.get() {
            allMetadata = cachedMetadata
            hasLoaded = true
            isLoading = false
            recompute()
        }
    }

    public func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    public func load() async {
        await refresh(showLoadingIndicator: !hasLoaded)
        await refreshUpcomingEvents(showLoadingIndicator: !hasLoaded)
    }

    public func refresh() async {
        await refresh(showLoadingIndicator: false)
        await refreshUpcomingEvents(showLoadingIndicator: false)
    }

    public func handleTranscriptionSaved(_ notification: Notification) async {
        let transcriptionID = (notification.userInfo?[AppNotifications.UserInfoKey.transcriptionId] as? String)
            .flatMap(UUID.init(uuidString:))

        guard let transcriptionID else {
            await refresh(showLoadingIndicator: false)
            return
        }

        do {
            guard let transcription = try await storage.loadTranscription(by: transcriptionID) else {
                await refresh(showLoadingIndicator: false)
                return
            }

            upsertMetadata(from: transcription)
            if storage is FileSystemStorageService {
                DashboardMetadataCache.set(allMetadata)
            }
            hasLoaded = true
            isLoading = false
            recompute()
        } catch {
            logger.error("Failed to update metadata incrementally: \(error.localizedDescription)")
            await refresh(showLoadingIndicator: false)
        }
    }

    private func refresh(showLoadingIndicator: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        if showLoadingIndicator {
            isLoading = true
        }
        errorMessage = nil

        do {
            allMetadata = try await storage.loadAllMetadata()
            if storage is FileSystemStorageService {
                DashboardMetadataCache.set(allMetadata)
            }
            hasLoaded = true
            recompute()
        } catch {
            logger.error("Failed to load metadata: \(error.localizedDescription)")
            errorMessage = "metrics.error.load".localized
        }

        if showLoadingIndicator {
            isLoading = false
        }
    }

    public func requestCalendarAccess() async {
        calendarPermissionState = await calendarEventService.requestAccess()
        await refreshUpcomingEvents(showLoadingIndicator: false)
    }

    public func openCalendarSettings() {
        calendarEventService.openSystemSettings()
    }

    public func linkCalendarEvent(_ event: MeetingCalendarEventSnapshot) {
        recordingManager.linkCurrentMeeting(to: event)
    }

    public func clearLinkedCalendarEvent() {
        recordingManager.linkCurrentMeeting(to: nil)
    }

    public func ignoreUpcomingEvent(_ event: MeetingCalendarEventSnapshot) {
        settingsStore.ignoreCalendarEventIdentifier(event.eventIdentifier)
        if activeLinkedCalendarEventID == event.eventIdentifier {
            clearLinkedCalendarEvent()
        }
        upcomingEvents.removeAll { $0.eventIdentifier == event.eventIdentifier }
    }

    public func isLinkedEvent(_ event: MeetingCalendarEventSnapshot) -> Bool {
        activeLinkedCalendarEventID == event.eventIdentifier
    }

    public func calendarEventNotesContent(for event: MeetingCalendarEventSnapshot) -> MeetingNotesContent {
        recordingManager.loadCalendarEventNotesContent(for: event.eventIdentifier)
    }

    public func updateCalendarEventNotes(_ content: MeetingNotesContent, for event: MeetingCalendarEventSnapshot) {
        recordingManager.updateCalendarEventNotes(content, for: event.eventIdentifier)
    }

    public func calendarEventNotes(for event: MeetingCalendarEventSnapshot) -> String {
        calendarEventNotesContent(for: event).plainText
    }

    public func updateCalendarEventNotes(_ notes: String, for event: MeetingCalendarEventSnapshot) {
        updateCalendarEventNotes(MeetingNotesContent(plainText: notes), for: event)
    }

    private func refreshUpcomingEvents(showLoadingIndicator: Bool) {
        calendarPermissionState = calendarEventService.authorizationState()

        guard calendarPermissionState.isAuthorized else {
            upcomingEvents = []
            isLoadingCalendar = false
            return
        }

        if showLoadingIndicator {
            isLoadingCalendar = true
        }

        do {
            upcomingEvents = try calendarEventService.fetchUpcomingEvents(
                limit: 10,
                now: Date(),
                window: 24 * 60 * 60,
                ignoredEventIdentifiers: settingsStore.ignoredCalendarEventIdentifiers()
            )
        } catch {
            logger.error("Failed to load upcoming calendar events: \(error.localizedDescription)")
            upcomingEvents = []
        }

        if showLoadingIndicator {
            isLoadingCalendar = false
        }
    }

    private func bindRecordingState() {
        settingsStore.$isMeetingTranscriptionEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                self?.isMeetingTranscriptionEnabled = isEnabled
            }
            .store(in: &cancellables)

        recordingManager.currentMeetingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] meeting in
                self?.activeLinkedCalendarEventID = meeting?.linkedCalendarEvent?.eventIdentifier
                Task { @MainActor [weak self] in
                    await self?.refreshUpcomingEvents(showLoadingIndicator: false)
                }
            }
            .store(in: &cancellables)

        recordingManager.isRecordingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording in
                self?.isRecording = isRecording
            }
            .store(in: &cancellables)
    }

    private func recompute() {
        let filtered = allMetadata.filter { metadata in
            guard dateFilter.contains(metadata.startTime) else { return false }
            switch metadata.capturePurpose {
            case .dictation: return showDictations
            case .meeting: return showMeetings
            }
        }
        summary = MetricsAggregator.computeSummary(
            metadata: filtered,
            baselineTypingWordsPerMinute: Self.DEFAULT_BASELINE_WPM
        )
        weekdayBuckets = MetricsAggregator.computeWeekdayBuckets(metadata: filtered)
        hourlyBuckets = MetricsAggregator.computeHourlyBuckets(metadata: filtered)
        dailyBuckets = MetricsAggregator.computeDailyBuckets(metadata: filtered)
        appUsageBuckets = MetricsAggregator.computeTopAppUsageBuckets(
            metadata: filtered,
            topLimit: 6,
            otherLabel: "metrics.apps.frequency.other".localized
        )
    }

    private func upsertMetadata(from transcription: Transcription) {
        let metadata = TranscriptionMetadata(
            id: transcription.id,
            meetingId: transcription.meeting.id,
            meetingTitle: transcription.meeting.preferredTitle,
            appName: transcription.meeting.appName,
            appRawValue: transcription.meeting.app.rawValue,
            appBundleIdentifier: transcription.meeting.appBundleIdentifier,
            startTime: transcription.meeting.startTime,
            createdAt: transcription.createdAt,
            previewText: String(transcription.text.prefix(100)),
            wordCount: transcription.wordCount,
            language: transcription.language,
            isPostProcessed: transcription.isPostProcessed,
            duration: transcription.meeting.duration,
            audioFilePath: transcription.meeting.audioFilePath,
            inputSource: transcription.inputSource
        )

        if let existingIndex = allMetadata.firstIndex(where: { $0.id == metadata.id }) {
            allMetadata[existingIndex] = metadata
        } else {
            allMetadata.append(metadata)
        }
    }
}

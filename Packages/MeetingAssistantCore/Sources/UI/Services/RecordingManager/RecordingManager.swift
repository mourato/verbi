import AVFoundation
import Combine
import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import os.log
import UserNotifications

/// Central manager coordinating recording, meeting detection, and transcription.
/// Orchestrates microphone and system audio recording with post-processing merge.
@MainActor
public class RecordingManager: ObservableObject, RecordingServiceProtocol {
    public static let shared = makeSharedManager()

    // MARK: - Recording Actor

    let recordingActor = RecordingActor()
    let lifecycleCoordinator = RecordingLifecycleCoordinator()

    // MARK: - Input Device

    let audioDeviceManager = AudioDeviceManager()
    let microphoneInputSelectionResolver: MicrophoneInputSelectionResolver

    // MARK: - Published State

    @Published public var isRecording = false
    @Published public var isStartingRecording = false
    @Published public var isTranscribing = false
    @Published public internal(set) var isForegroundTranscribing = false
    @Published public var meetingState: MeetingState = .idle
    @Published public var currentMeeting: Meeting?
    @Published public var lastError: Error?
    @Published public var hasRequiredPermissions = false
    @Published public var currentCapturePurpose: CapturePurpose?
    @Published public var recordingSource: RecordingSource = .microphone
    @Published public var isMeetingMicrophoneEnabled = false
    @Published public var isMeetingNotesPanelVisible = false
    @Published public var currentMeetingNotesText = ""
    @Published public var currentMeetingNotesRichTextData: Data?
    @Published public var dictationSessionOutputLanguageOverride: DictationOutputLanguage?
    @Published public var postProcessingReadinessWarningIssue: EnhancementsInferenceReadinessIssue?
    @Published public var postProcessingReadinessWarningMode: IntelligenceKernelMode?
    @Published public internal(set) var automaticMeetingRecordingConfirmation: AutomaticMeetingRecordingConfirmation?

    // MARK: - Protocol Publishers

    public var meetingStatePublisher: AnyPublisher<MeetingState, Never> {
        $meetingState.eraseToAnyPublisher()
    }

    public var isRecordingPublisher: AnyPublisher<Bool, Never> {
        $isRecording.eraseToAnyPublisher()
    }

    public var isTranscribingPublisher: AnyPublisher<Bool, Never> {
        $isTranscribing.eraseToAnyPublisher()
    }

    public var isForegroundTranscribingPublisher: AnyPublisher<Bool, Never> {
        $isForegroundTranscribing.eraseToAnyPublisher()
    }

    public var isStartingPublisher: AnyPublisher<Bool, Never> {
        $isStartingRecording.eraseToAnyPublisher()
    }

    public var currentMeetingPublisher: AnyPublisher<Meeting?, Never> {
        $currentMeeting.eraseToAnyPublisher()
    }

    /// Detailed transcription service status for UI feedback.
    public let transcriptionStatus = TranscriptionStatus()

    /// Individual permission status tracking for UI display.
    public let permissionStatus = PermissionStatusManager()

    // MARK: - Services

    let micRecorder: any AudioRecordingService
    let systemRecorder: any AudioRecordingService
    let audioMerger: AudioMerger
    let audioSilenceCompactor: any AudioSilenceCompacting
    let meetingDetector: MeetingDetector
    let transcriptionClient: any TranscriptionService
    let postProcessingRepository: any PostProcessingRepository
    let calendarEventService: any CalendarEventServiceProtocol
    let storage: any StorageService
    let notificationService: NotificationService
    let contextAwarenessService: any ContextAwarenessServiceProtocol
    let textContextProvider: any TextContextProvider
    let textContextGuardrails: TextContextGuardrails
    let textContextPolicy: TextContextPolicy
    let transcribeAudioUseCase: TranscribeAudioUseCase
    let meetingNotesRichTextStore: any MeetingNotesRichTextStoreProtocol
    let meetingNotesMarkdownStore: any MeetingNotesMarkdownDocumentStoreProtocol
    let transcriptPreprocessor = TranscriptIntelligencePreprocessor()
    let activeAppContextProvider: any ActiveAppContextProvider
    let captureContextResolver: any CaptureContextResolving
    let audioKernelProvider: AudioKernelProvider
    let apiKeyExists: (AIProvider) -> Bool
    let transcriptionAPIKeyExists: (TranscriptionProvider) -> Bool
    let isLocalRetryModelReady: (LocalTranscriptionModel) -> Bool
    let audioPreparationService: AudioPreparationService
    let calendarIntegrationService: MeetingCalendarIntegrationService
    let contextCaptureService: AssistantContextCaptureService
    let postProcessingConfigurationProvider: PostProcessingConfigurationProvider
    var browserProviders: [String: BrowserActiveTabURLProviding] = BrowserProviderRegistry.defaultProviders()

    var cancellables = Set<AnyCancellable>()
    var automaticMeetingRecordingCancellable: AnyCancellable?
    var automaticMeetingRecordingConfirmationTask: Task<Void, Never>?
    var automaticMeetingRecordingStopTask: Task<Void, Never>?
    var statusCheckTask: Task<Void, Never>?
    var isStartOperationInFlight = false
    var postStartContextCaptureTask: Task<Void, Never>?
    var postStartWindowOCRCaptureTask: Task<Void, Never>?
    var deferredIncrementalWarmupTask: Task<Void, Never>?
    var estimatedPostProcessingProgressTask: Task<Void, Never>?
    var estimatedPostProcessingProgressSessionID: UUID?
    var activeStartTelemetry: RecordingStartTelemetry?
    var postProcessingContext: String?
    var postProcessingContextItems: [TranscriptionContextItem] = []
    var activePostProcessingKernelMode: IntelligenceKernelMode?
    var dictationStartBundleIdentifier: String?
    var dictationStartURL: URL?
    var activeDictationStyleSnapshot: DictationStyle?
    var activeTranscriptionConfiguration: DomainTranscriptionRequestConfiguration?
    var activeVocabularySnapshot: VocabularySnapshot?
    var activeUseCaseConfig: UseCaseConfig?
    var activeAutoExportSummaries: Bool?
    var activeDeliverySettings: DeliverySettingsSnapshot?
    var activeTranscriptionSessionIDs = Set<UUID>()
    var foregroundTranscriptionSessionID: UUID?
    var incrementalDictationCoordinator: IncrementalTranscriptionCoordinator?
    var incrementalMeetingCoordinator: IncrementalTranscriptionCoordinator?
    var incrementalBufferForwarder: IncrementalBufferForwarder?

    var concreteMicRecorder: AudioRecorder? {
        micRecorder as? AudioRecorder
    }

    struct RecordingStartTelemetry {
        let traceID = UUID().uuidString
        let triggerLabel: String
        let source: RecordingSource
        let requestedAt: Date
        let managerEntryAt: Date
        var recorderStartedAt: Date?
        var indicatorShownAt: Date?
    }

    struct TranscriptionSessionSnapshot {
        let id: UUID
        let meeting: Meeting
        let recordingSource: RecordingSource
        let kernelMode: IntelligenceKernelMode
        let postProcessingContext: String?
        let postProcessingContextItems: [TranscriptionContextItem]
        let meetingNotesContent: MeetingNotesContent
        let dictationSessionOutputLanguageOverride: DictationOutputLanguage?
        let dictationStartBundleIdentifier: String?
        let dictationStartURL: URL?
        let dictationStyleID: UUID?
        let dictationTextHandlingPolicy: DictationTextHandlingPolicy?
        let dictationTranscriptionConfiguration: DictationTranscriptionConfiguration?
        let transcriptionConfiguration: DomainTranscriptionRequestConfiguration?
        let dictationEnhancementsSelection: EnhancementsAISelection?
        let postProcessingEnhancementsSelection: EnhancementsAISelection?
        let dictationPostProcessingEnabled: Bool?
        let dictationStyle: DictationStyle?
        let vocabularySnapshot: VocabularySnapshot
        var useCaseConfig: UseCaseConfig?
        let autoExportSummaries: Bool
        let deliverySettings: DeliverySettingsSnapshot?

        init(
            id: UUID,
            meeting: Meeting,
            recordingSource: RecordingSource,
            kernelMode: IntelligenceKernelMode,
            postProcessingContext: String?,
            postProcessingContextItems: [TranscriptionContextItem],
            meetingNotesContent: MeetingNotesContent,
            dictationSessionOutputLanguageOverride: DictationOutputLanguage?,
            dictationStartBundleIdentifier: String?,
            dictationStartURL: URL?,
            dictationStyleID: UUID? = nil,
            dictationTextHandlingPolicy: DictationTextHandlingPolicy? = nil,
            dictationTranscriptionConfiguration: DictationTranscriptionConfiguration? = nil,
            transcriptionConfiguration: DomainTranscriptionRequestConfiguration? = nil,
            dictationEnhancementsSelection: EnhancementsAISelection? = nil,
            postProcessingEnhancementsSelection: EnhancementsAISelection? = nil,
            dictationPostProcessingEnabled: Bool? = nil,
            dictationStyle: DictationStyle? = nil,
            vocabularySnapshot: VocabularySnapshot = .empty,
            useCaseConfig: UseCaseConfig? = nil,
            autoExportSummaries: Bool = false,
            deliverySettings: DeliverySettingsSnapshot? = nil
        ) {
            self.id = id
            self.meeting = meeting
            self.recordingSource = recordingSource
            self.kernelMode = kernelMode
            self.postProcessingContext = postProcessingContext
            self.postProcessingContextItems = postProcessingContextItems
            self.meetingNotesContent = meetingNotesContent
            self.dictationSessionOutputLanguageOverride = dictationSessionOutputLanguageOverride
            self.dictationStartBundleIdentifier = dictationStartBundleIdentifier
            self.dictationStartURL = dictationStartURL
            self.dictationStyleID = dictationStyleID
            self.dictationTextHandlingPolicy = dictationTextHandlingPolicy
            self.dictationTranscriptionConfiguration = dictationTranscriptionConfiguration
            self.transcriptionConfiguration = transcriptionConfiguration
            self.dictationEnhancementsSelection = dictationEnhancementsSelection
            self.postProcessingEnhancementsSelection = postProcessingEnhancementsSelection
            self.dictationPostProcessingEnabled = dictationPostProcessingEnabled
            self.dictationStyle = dictationStyle
            self.vocabularySnapshot = vocabularySnapshot
            self.useCaseConfig = useCaseConfig
            self.autoExportSummaries = autoExportSummaries
            self.deliverySettings = deliverySettings
        }
    }

    // MARK: - Constants

    enum Constants {
        static let processingProgress: Double = 10.0
        static let postProcessingProgress: Double = 90.0
        static let aiProcessingProgress: Double = 92.0
        static let postProcessingProgressCeiling: Double = 99.0
        static let postProcessingProgressSmoothingTau: TimeInterval = 35.0
        static let postProcessingProgressTickNanoseconds: UInt64 = 300_000_000
        static let statusResetDelay: Int = 3
        static let startContextCaptureTimeout: UInt64 = 1_500_000_000
        static let deferredIncrementalWarmupDelay: UInt64 = 3_000_000_000
    }

    private static func defaultTextContextProvider() -> any TextContextProvider {
        AXTextContextProvider(
            exclusionPolicyProvider: {
                TextContextExclusionPolicy()
            },
            customExcludedBundleIDsProvider: {
                AppSettingsStore.shared.contextAwarenessExcludedBundleIDs
            }
        )
    }

    private static func makeSharedManager() -> RecordingManager {
        RecordingManager(
            micRecorder: AudioRecorder.shared,
            systemRecorder: SystemAudioRecorder.shared,
            transcriptionClient: TranscriptionClient.shared,
            postProcessingService: PostProcessingService.shared,
            calendarEventService: CalendarEventService.shared,
            audioMerger: AudioMerger(),
            audioSilenceCompactor: AudioSilenceCompactor(kernelProvider: .live),
            meetingDetector: MeetingDetector.shared,
            storage: FileSystemStorageService.shared,
            notificationService: .shared,
            contextAwarenessService: ContextAwarenessService.shared,
            textContextProvider: defaultTextContextProvider(),
            textContextGuardrails: TextContextGuardrails(),
            textContextPolicy: .default,
            activeAppContextProvider: NSWorkspaceActiveAppContextProvider(),
            captureContextResolver: CaptureContextResolver.shared,
            audioKernelProvider: .live,
            meetingNotesRichTextStore: MeetingNotesRichTextStore(),
            meetingNotesMarkdownStore: MeetingNotesMarkdownDocumentStore.shared,
            apiKeyExists: { provider in
                KeychainManager.existsAPIKey(for: provider)
            },
            transcriptionAPIKeyExists: { provider in
                KeychainManager.existsTranscriptionAPIKey(for: provider)
            },
            isLocalRetryModelReady: { model in
                FluidAIModelManager.shared.isASRModelInstalled(localModelID: model.rawValue)
            }
        )
    }

    // MARK: - Computed Properties for Actor State

    func getMicAudioURL() async -> URL? {
        await recordingActor.micAudioURLState
    }

    func getSystemAudioURL() async -> URL? {
        await recordingActor.systemAudioURLState
    }

    func getMergedAudioURL() async -> URL? {
        await recordingActor.mergedAudioURLState
    }

    func setMicAudioURL(_ url: URL?) async {
        await recordingActor.setMicAudioURL(url)
    }

    func setSystemAudioURL(_ url: URL?) async {
        await recordingActor.setSystemAudioURL(url)
    }

    func setMergedAudioURL(_ url: URL?) async {
        await recordingActor.setMergedAudioURL(url)
    }

    // MARK: - Initialization

    public init(
        micRecorder: any AudioRecordingService = AudioRecorder.shared,
        systemRecorder: any AudioRecordingService = SystemAudioRecorder.shared,
        transcriptionClient: any TranscriptionService = TranscriptionClient.shared,
        postProcessingService: any PostProcessingServiceProtocol = PostProcessingService.shared,
        calendarEventService: any CalendarEventServiceProtocol = CalendarEventService.shared,
        audioMerger: AudioMerger = AudioMerger(),
        audioSilenceCompactor: any AudioSilenceCompacting = AudioSilenceCompactor(),
        meetingDetector: MeetingDetector = MeetingDetector.shared,
        storage: any StorageService = FileSystemStorageService.shared,
        notificationService: NotificationService = .shared,
        contextAwarenessService: any ContextAwarenessServiceProtocol = ContextAwarenessService.shared,
        textContextProvider: (any TextContextProvider)? = nil,
        textContextGuardrails: TextContextGuardrails = TextContextGuardrails(),
        textContextPolicy: TextContextPolicy = .default,
        activeAppContextProvider: any ActiveAppContextProvider = NSWorkspaceActiveAppContextProvider(),
        captureContextResolver: any CaptureContextResolving = CaptureContextResolver.shared,
        audioKernelProvider: AudioKernelProvider = .live,
        meetingNotesRichTextStore: any MeetingNotesRichTextStoreProtocol = MeetingNotesRichTextStore(),
        meetingNotesMarkdownStore: any MeetingNotesMarkdownDocumentStoreProtocol = MeetingNotesMarkdownDocumentStore.shared,
        audioPreparationService: AudioPreparationService? = nil,
        calendarIntegrationService: MeetingCalendarIntegrationService? = nil,
        contextCaptureService: AssistantContextCaptureService? = nil,
        postProcessingConfigurationProvider: PostProcessingConfigurationProvider? = nil,
        apiKeyExists: @escaping (AIProvider) -> Bool = { provider in
            KeychainManager.existsAPIKey(for: provider)
        },
        transcriptionAPIKeyExists: @escaping (TranscriptionProvider) -> Bool = { provider in
            KeychainManager.existsTranscriptionAPIKey(for: provider)
        },
        isLocalRetryModelReady: @escaping (LocalTranscriptionModel) -> Bool = { model in
            FluidAIModelManager.shared.isASRModelInstalled(localModelID: model.rawValue)
        }
    ) {
        self.micRecorder = micRecorder
        self.systemRecorder = systemRecorder
        self.transcriptionClient = transcriptionClient
        let postProcessingRepository = PostProcessingRepositoryAdapter(postProcessingService: postProcessingService)
        self.postProcessingRepository = postProcessingRepository
        self.calendarEventService = calendarEventService
        self.audioMerger = audioMerger
        self.audioSilenceCompactor = audioSilenceCompactor
        self.meetingDetector = meetingDetector
        self.storage = storage
        self.notificationService = notificationService
        self.contextAwarenessService = contextAwarenessService
        self.textContextProvider = textContextProvider ?? Self.defaultTextContextProvider()
        self.textContextGuardrails = textContextGuardrails
        self.textContextPolicy = textContextPolicy
        self.activeAppContextProvider = activeAppContextProvider
        self.captureContextResolver = captureContextResolver
        self.audioKernelProvider = audioKernelProvider
        self.meetingNotesRichTextStore = meetingNotesRichTextStore
        self.meetingNotesMarkdownStore = meetingNotesMarkdownStore
        self.apiKeyExists = apiKeyExists
        self.transcriptionAPIKeyExists = transcriptionAPIKeyExists
        self.isLocalRetryModelReady = isLocalRetryModelReady
        self.audioPreparationService = audioPreparationService ?? AudioPreparationService(
            audioSilenceCompactor: audioSilenceCompactor,
            settings: .shared,
            cleanupTemporaryFiles: { urls in
                storage.cleanupTemporaryFiles(urls: urls)
            }
        )
        self.calendarIntegrationService = calendarIntegrationService ?? MeetingCalendarIntegrationService(
            calendarEventService: calendarEventService
        )
        self.contextCaptureService = contextCaptureService ?? AssistantContextCaptureService(
            contextAwarenessService: contextAwarenessService,
            textContextProvider: self.textContextProvider,
            textContextGuardrails: textContextGuardrails,
            textContextPolicy: textContextPolicy
        )
        self.postProcessingConfigurationProvider = postProcessingConfigurationProvider ?? PostProcessingConfigurationProvider(
            apiKeyExists: apiKeyExists
        )
        microphoneInputSelectionResolver = MicrophoneInputSelectionResolver(deviceManager: audioDeviceManager)

        // Initialize UseCase with Adapters
        transcribeAudioUseCase = TranscribeAudioUseCase(
            transcriptionRepository: TranscriptionRepositoryAdapter(transcriptionService: transcriptionClient),
            transcriptionStorageRepository: CoreDataTranscriptionStorageRepository(stack: .shared),
            postProcessingRepository: postProcessingRepository
        )

        setupBindings()
        setupRecorderErrorForwarding()
        if isRunningAsAppBundle {
            let settings = AppSettingsStore.shared
            setAutomaticMeetingRecordingEnabled(settings.isMeetingTranscriptionEnabled && settings.autoStartRecording)
        }
        notificationService.requestAuthorization()
        Task { @Sendable [weak self] in
            await self?.checkPermission()
            if self?.isRunningAsAppBundle == true {
                await self?.startStatusMonitoring()
                await self?.runMeetingNotesMarkdownBackfillIfNeeded()
            }
            await self?.syncStateFromActor()
        }
    }

    deinit {
        AppLogger.debug("RecordingManager deinitialized", category: .recordingManager)
    }

    /// Sync local state from the recording actor (used on initialization).
    private func syncStateFromActor() async {
        isRecording = await recordingActor.recordingState
        isTranscribing = await recordingActor.transcribingState
        currentMeeting = await recordingActor.currentMeetingState
        currentCapturePurpose = currentMeeting?.capturePurpose
        lastError = await recordingActor.lastErrorState
        hasRequiredPermissions = await recordingActor.permissionsState
    }

    /// Check if running as a proper app bundle (required for UNUserNotificationCenter).
    private var isRunningAsAppBundle: Bool {
        guard let bundleId = Bundle.main.bundleIdentifier else { return false }
        return !bundleId.lowercased().contains("xctest")
    }
}

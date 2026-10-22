// swiftlint:disable file_length

import AppKit
import Combine
import Foundation
import MeetingAssistantCore
import MeetingAssistantCoreAudio

// MARK: - Mock Audio Recording Service

class MockAudioRecorder: AudioRecordingService {
    @Published var isRecording = false
    var isRecordingPublisher: AnyPublisher<Bool, Never> {
        $isRecording.eraseToAnyPublisher()
    }

    var currentRecordingURL: URL?
    var error: Error?

    var shouldFailStart = false
    var permissionGranted = true
    var permissionState: PermissionState = .granted

    var startRecordingCalled = false
    var stopRecordingCalled = false

    // Call tracking properties
    var startRecordingParams: [(url: URL, retryCount: Int)] = []
    var stopRecordingCalledCount = 0

    func startRecording(to outputURL: URL, retryCount: Int) async throws {
        startRecordingParams.append((outputURL, retryCount))

        if shouldFailStart {
            throw NSError(domain: "MockRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mock failure"])
        }
        startRecordingCalled = true
        isRecording = true
        currentRecordingURL = outputURL
    }

    func stopRecording() async -> URL? {
        stopRecordingCalledCount += 1
        stopRecordingCalled = true
        isRecording = false
        return currentRecordingURL
    }

    func hasPermission() async -> Bool {
        permissionGranted
    }

    func requestPermission() async {
        // no-op
    }

    func getPermissionState() -> PermissionState {
        permissionState
    }

    func openSettings() {
        // no-op
    }
}

// MARK: - Mock CaptureArtifact Service

class MockTranscriptionClient: TranscriptionService, TranscriptionServiceFinalDiarization {
    @Published var isTranscribing = false

    var shouldFailHealthCheck = false
    var shouldFailTranscription = false
    var shouldFailDiarization = false
    var mockText = "Mock transcription text"
    var mockLanguage = "pt"
    var mockDurationSeconds = 10.0
    var mockModel = "mock-model"
    var mockConfidenceScore: Double?
    var mockSegments: [CaptureArtifact.Segment] = []
    var mockSpeakerTimeline: [SpeakerTimelineSegment] = []

    // Call tracking properties
    var healthCheckCallCount = 0
    var fetchServiceStatusCallCount = 0
    var transcribeCallCount = 0
    var fileTranscribeCallCount = 0
    var sampleTranscribeCallCount = 0
    var diarizeCallCount = 0
    var assignSpeakersCallCount = 0
    var lastTranscribeAudioURL: URL?
    var lastTranscribeSamples: [Float] = []
    var lastTranscriptionConfiguration: DomainTranscriptionRequestConfiguration?

    func healthCheck() async throws -> Bool {
        healthCheckCallCount += 1
        if shouldFailHealthCheck {
            return false
        }
        return true
    }

    func fetchServiceStatus() async throws -> ServiceStatusResponse {
        fetchServiceStatusCallCount += 1
        return ServiceStatusResponse(
            status: "ready",
            modelState: "loaded",
            modelLoaded: true,
            device: "cpu",
            modelName: "mock-model",
            uptimeSeconds: 100,
            lastTranscriptionTime: nil,
            totalTranscriptions: 0,
            totalAudioProcessedSeconds: 0,
        )
    }

    func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)? = nil,
    ) async throws -> TranscriptionResponse {
        transcribeCallCount += 1
        fileTranscribeCallCount += 1
        lastTranscribeAudioURL = audioURL

        // Simulate progress updates if callback provided
        if let onProgress {
            onProgress(25.0)
            onProgress(50.0)
            onProgress(75.0)
            onProgress(100.0)
        }

        if shouldFailTranscription {
            throw NSError(domain: "MockTranscription", code: 2, userInfo: [NSLocalizedDescriptionKey: "Transcription failed"])
        }
        return TranscriptionResponse(
            text: mockText,
            segments: mockSegments,
            language: mockLanguage,
            durationSeconds: mockDurationSeconds,
            model: mockModel,
            processedAt: Date().ISO8601Format(),
            confidenceScore: mockConfidenceScore,
        )
    }

    func transcribe(samples: [Float]) async throws -> TranscriptionResponse {
        transcribeCallCount += 1
        sampleTranscribeCallCount += 1
        lastTranscribeSamples = samples

        if shouldFailTranscription {
            throw NSError(domain: "MockTranscription", code: 2, userInfo: [NSLocalizedDescriptionKey: "Transcription failed"])
        }

        return TranscriptionResponse(
            text: mockText,
            segments: mockSegments,
            language: mockLanguage,
            durationSeconds: mockDurationSeconds,
            model: mockModel,
            processedAt: Date().ISO8601Format(),
            confidenceScore: mockConfidenceScore,
        )
    }

    func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        executionMode _: CaptureMode,
        diarizationEnabledOverride _: Bool?,
        configuration: DomainTranscriptionRequestConfiguration,
    ) async throws -> TranscriptionResponse {
        lastTranscriptionConfiguration = configuration
        return try await transcribe(audioURL: audioURL, onProgress: onProgress)
    }

    func transcribe(
        samples: [Float],
        configuration: DomainTranscriptionRequestConfiguration,
    ) async throws -> TranscriptionResponse {
        lastTranscriptionConfiguration = configuration
        return try await transcribe(samples: samples)
    }

    func supportsIncrementalTranscription(selection _: TranscriptionProviderSelection) -> Bool {
        true
    }

    func diarize(audioURL: URL) async throws -> [SpeakerTimelineSegment] {
        diarizeCallCount += 1
        lastTranscribeAudioURL = audioURL
        if shouldFailDiarization {
            throw NSError(domain: "MockTranscription", code: 3, userInfo: [NSLocalizedDescriptionKey: "Diarization failed"])
        }
        return mockSpeakerTimeline
    }

    func assignSpeakers(
        to segments: [CaptureArtifact.Segment],
        using speakerTimeline: [SpeakerTimelineSegment],
    ) -> [CaptureArtifact.Segment] {
        assignSpeakersCallCount += 1
        guard !speakerTimeline.isEmpty else { return segments }

        return segments.map { segment in
            let midPoint = (segment.startTime + segment.endTime) / 2.0
            let speaker = speakerTimeline.first {
                $0.startTime <= midPoint && $0.endTime >= midPoint
            }?.speaker ?? segment.speaker
            return CaptureArtifact.Segment(
                id: segment.id,
                speaker: speaker,
                text: segment.text,
                startTime: segment.startTime,
                endTime: segment.endTime,
            )
        }
    }
}

// MARK: - Mock Post Processing Service

@MainActor
class MockPostProcessingService: PostProcessingServiceProtocol {
    @Published var isProcessing = false
    var isProcessingPublisher: AnyPublisher<Bool, Never> {
        $isProcessing.eraseToAnyPublisher()
    }

    var lastError: PostProcessingError?

    var shouldFail = false
    var processTranscriptionCallCount = 0
    var lastProcessText: String?
    var lastPrompt: PostProcessingPrompt?
    var lastPromptTitle: String?
    var lastPromptText: String?
    var lastMode: CaptureMode?
    var lastSystemPromptOverride: String?
    var lastRequest: PostProcessingRequest?
    var lastStructuredRequest: PostProcessingRequest?

    func processTranscription(_ text: String, request: PostProcessingRequest) async throws -> String {
        lastRequest = request
        let prompt = request.prompt ?? .defaultPrompt
        return try await processTranscription(
            text,
            with: prompt,
            mode: request.mode,
            systemPromptOverride: request.systemPromptOverride,
        )
    }

    func processTranscriptionStructured(
        _ transcription: String,
        request: PostProcessingRequest,
    ) async throws -> DomainPostProcessingResult {
        lastStructuredRequest = request
        let prompt = request.prompt ?? .defaultPrompt
        return try await processTranscriptionStructured(
            transcription,
            with: prompt,
            mode: request.mode,
        )
    }

    func processTranscription(_ text: String, with prompt: PostProcessingPrompt) async throws -> String {
        processTranscriptionCallCount += 1
        lastProcessText = text
        lastPrompt = prompt
        lastPromptTitle = prompt.title
        lastPromptText = prompt.promptText

        if shouldFail {
            throw PostProcessingError.apiError("Mock failure")
        }
        return "Processed: \(text)"
    }

    func processTranscription(
        _ text: String,
        with prompt: PostProcessingPrompt,
        mode: CaptureMode,
        systemPromptOverride: String?,
    ) async throws -> String {
        lastMode = mode
        lastSystemPromptOverride = systemPromptOverride
        return try await processTranscription(text, with: prompt)
    }

    func processTranscription(_ text: String) async throws -> String {
        try await processTranscription(text, with: PostProcessingPrompt(
            id: UUID(),
            title: "Default",
            promptText: "Fix this: {{TRANSCRIPTION}}",
            isActive: true,
        ))
    }

    func processTranscriptionStructured(_ transcription: String) async throws -> DomainPostProcessingResult {
        let processedText = try await processTranscription(transcription)
        let summary = CanonicalSummary(
            title: processedText,
            summary: processedText,
            trustFlags: .init(
                isGroundedInTranscript: true,
                containsSpeculation: false,
                isHumanReviewed: false,
                confidenceScore: 0.8,
            ),
        )
        return DomainPostProcessingResult(
            processedText: processedText,
            canonicalSummary: summary,
            outputState: .structured,
        )
    }

    func processTranscriptionStructured(
        _ transcription: String,
        with prompt: PostProcessingPrompt,
    ) async throws -> DomainPostProcessingResult {
        let processedText = try await processTranscription(transcription, with: prompt)
        let summary = CanonicalSummary(
            title: processedText,
            summary: processedText,
            trustFlags: .init(
                isGroundedInTranscript: true,
                containsSpeculation: false,
                isHumanReviewed: false,
                confidenceScore: 0.8,
            ),
        )
        return DomainPostProcessingResult(
            processedText: processedText,
            canonicalSummary: summary,
            outputState: .structured,
        )
    }

    func processTranscriptionStructured(
        _ transcription: String,
        with prompt: PostProcessingPrompt,
        mode _: CaptureMode,
    ) async throws -> DomainPostProcessingResult {
        try await processTranscriptionStructured(
            transcription,
            with: prompt,
        )
    }
}

// MARK: - Mock CaptureSession Q&A Service

@MainActor
class MockMeetingQAService: MeetingQAServiceProtocol {
    @Published var isAnswering = false
    var lastError: MeetingQAError?

    var askCallCount = 0
    var lastQuestion: String?
    var lastRequest: IntelligenceKernelQuestionRequest?
    var nextResponse = MeetingQAResponse(
        status: .answered,
        answer: "Mock answer",
        evidence: [
            MeetingQAEvidence(
                speaker: "Speaker 1",
                startTime: 0,
                endTime: 5,
                excerpt: "Mock evidence",
            ),
        ],
    )
    var nextError: MeetingQAError?

    func ask(_ request: IntelligenceKernelQuestionRequest) async throws -> MeetingQAResponse {
        lastRequest = request
        return try await ask(question: request.question, transcription: request.transcription)
    }

    func ask(question: String, transcription _: CaptureArtifact) async throws -> MeetingQAResponse {
        askCallCount += 1
        lastQuestion = question

        if let nextError {
            lastError = nextError
            throw nextError
        }

        return nextResponse
    }
}

// MARK: - Mock Storage Service

class MockStorageService: StorageService, @unchecked Sendable {
    var recordingsDirectory: URL = .init(fileURLWithPath: "/tmp/mock/recordings")

    var createRecordingURLCalled = false
    var cleanupTemporaryFilesCalled = false
    var saveTranscriptionCalled = false
    var savedTranscriptions: [CaptureArtifact] = []
    var savedModelPerformanceAttempts: [ModelPerformanceAttempt] = []

    // Call tracking properties
    var createRecordingURLParams: [(meeting: CaptureSession, type: RecordingType)] = []
    var loadTranscriptionsCallCount = 0
    var loadAllMetadataCallCount = 0
    var loadMetadataCallCount = 0
    var metadataQueries: [TranscriptionMetadataQuery] = []

    /// Mock data for testing
    var mockTranscriptions: [CaptureArtifact] = []

    func createRecordingURL(for meeting: CaptureSession, type: RecordingType) -> URL {
        createRecordingURLParams.append((meeting, type))
        createRecordingURLCalled = true
        return recordingsDirectory.appendingPathComponent("mock_\(type.rawValue).wav")
    }

    func cleanupTemporaryFiles(urls: [URL]) {
        cleanupTemporaryFilesCalled = true
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func saveTranscription(_ transcription: CaptureArtifact) async throws {
        saveTranscriptionCalled = true
        savedTranscriptions.append(transcription)
        if let existingIndex = mockTranscriptions.firstIndex(where: { $0.id == transcription.id }) {
            mockTranscriptions[existingIndex] = transcription
        } else {
            mockTranscriptions.append(transcription)
        }
    }

    func saveModelPerformanceAttempt(_ attempt: ModelPerformanceAttempt) async throws {
        savedModelPerformanceAttempts.append(attempt)
    }

    func loadTranscriptions() async throws -> [CaptureArtifact] {
        loadTranscriptionsCallCount += 1
        return mockTranscriptions
    }

    func loadAllMetadata() async throws -> [TranscriptionMetadata] {
        loadAllMetadataCallCount += 1
        return allMetadata()
    }

    func loadMetadata(matching query: TranscriptionMetadataQuery) async throws -> [TranscriptionMetadata] {
        loadMetadataCallCount += 1
        metadataQueries.append(query)
        return allMetadata()
            .filter { metadata in
                query.includeNonVisibleLifecycleStates || metadata.lifecycleState.isVisibleInHistory
            }
            .filter { metadata in
                switch query.capturePurposeFilter {
                case .all:
                    true
                case .dictations:
                    metadata.capturePurpose == .dictation
                case .meetings:
                    metadata.capturePurpose == .meeting
                }
            }
            .filter { metadata in
                query.dateFilter.contains(metadata.createdAt)
            }
            .filter { metadata in
                guard let appRawValue = query.appRawValue else { return true }
                return metadata.appRawValue == appRawValue
            }
            .filter { metadata in
                let trimmed = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return true }

                let queryText = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                let preview = metadata.previewText.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                let appName = metadata.appName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                let meetingTitle = metadata.capturePurpose.supportsMeetingConversation
                    ? (
                        metadata.meetingTitle?
                            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) ?? ""
                    )
                    : ""
                return preview.contains(queryText) || appName.contains(queryText) || meetingTitle.contains(queryText)
            }
            .sorted { query.sortNewestFirst ? $0.createdAt > $1.createdAt : $0.createdAt < $1.createdAt }
            .prefix(query.limit.map { max($0, 0) } ?? Int.max)
            .map(\.self)
    }

    func loadModelPerformanceAttempts(matching query: ModelPerformanceAttemptQuery) async throws -> [ModelPerformanceAttempt] {
        let attempts = savedModelPerformanceAttempts
            .filter { $0.stage == query.stage }
            .filter { attempt in
                switch query.captureFilter {
                case .all:
                    true
                case .dictation:
                    attempt.capturePurpose == .dictation
                case .meeting:
                    attempt.capturePurpose == .meeting
                }
            }
            .filter { query.dateFilter.contains($0.startedAt) }
            .filter { attempt in
                guard let providerID = query.providerID else { return true }
                return attempt.modelIdentity.providerID == providerID
            }
            .filter { attempt in
                switch query.statusFilter {
                case .all:
                    true
                case .succeeded:
                    attempt.status == .succeeded
                case .failed:
                    attempt.status == .failed
                }
            }
            .filter { attempt in
                let trimmed = query.modelSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return true }
                return attempt.modelIdentity.modelDisplayName.localizedCaseInsensitiveContains(trimmed)
                    || attempt.modelIdentity.modelID.localizedCaseInsensitiveContains(trimmed)
                    || attempt.modelIdentity.providerDisplayName.localizedCaseInsensitiveContains(trimmed)
            }
            .sorted { $0.startedAt > $1.startedAt }

        if let limit = query.limit {
            return Array(attempts.prefix(max(limit, 0)))
        }

        return attempts
    }

    private func allMetadata() -> [TranscriptionMetadata] {
        mockTranscriptions.map { transcription in
            TranscriptionMetadata(
                id: transcription.id,
                meetingId: transcription.meeting.id,
                meetingTitle: transcription.meeting.preferredTitle,
                appName: transcription.meeting.appName,
                appRawValue: transcription.meeting.app.rawValue,
                capturePurpose: transcription.capturePurpose,
                appBundleIdentifier: transcription.meeting.appBundleIdentifier,
                startTime: transcription.meeting.startTime,
                createdAt: transcription.createdAt,
                previewText: transcription.preview,
                wordCount: transcription.wordCount,
                language: transcription.language,
                isPostProcessed: transcription.isPostProcessed,
                duration: transcription.meeting.duration,
                audioFilePath: transcription.meeting.audioFilePath,
                inputSource: transcription.inputSource,
                lifecycleState: transcription.lifecycleState,
            )
        }
    }

    func loadTranscription(by id: UUID) async throws -> CaptureArtifact? {
        mockTranscriptions.first(where: { $0.id == id })
    }

    func deleteTranscription(by id: UUID) async throws {
        mockTranscriptions.removeAll(where: { $0.id == id })
    }

    func cleanupOldTranscriptions(olderThanDays days: Int) async throws {
        // Mock implementation
    }

    func computeRetentionCleanupPreview(olderThanDays days: Int) async throws -> RetentionCleanupPreview {
        RetentionCleanupPreview(
            retentionDays: days,
            audioFiles: []
        )
    }

    func performRetentionCleanup(preview: RetentionCleanupPreview) async throws -> RetentionCleanupResult {
        RetentionCleanupResult(
            deletedAudioCount: preview.audioCount
        )
    }
}

// MARK: - Mock Active App Context

@MainActor
final class MockActiveAppContextProvider: ActiveAppContextProvider {
    var activeContext: ActiveAppContext?

    func fetchActiveAppContext() async throws -> ActiveAppContext? {
        activeContext
    }
}

final class MockAudioSilenceCompactor: AudioSilenceCompacting, @unchecked Sendable {
    var compactCallCount = 0
    var lastInputURL: URL?
    var lastOutputURL: URL?
    var lastFormat: AppSettingsStore.AudioFormat?
    var shouldThrow = false
    var materializeOutputFile = true
    var nextWasCompacted = true
    var nextRemovedRatio = 0.4

    func compactForTranscription(
        inputURL: URL,
        outputURL: URL,
        format: AppSettingsStore.AudioFormat,
    ) async throws -> AudioCompactionResult {
        compactCallCount += 1
        lastInputURL = inputURL
        lastOutputURL = outputURL
        lastFormat = format

        if shouldThrow {
            throw AudioSilenceCompactorError.exportFailed(nil)
        }

        if materializeOutputFile, nextWasCompacted {
            FileManager.default.createFile(atPath: outputURL.path, contents: Data("temp".utf8))
        }

        let resolvedOutputURL = nextWasCompacted ? outputURL : inputURL
        return AudioCompactionResult(
            outputURL: resolvedOutputURL,
            originalDuration: 10,
            compactedDuration: nextWasCompacted ? 6 : 10,
            removedDuration: nextWasCompacted ? 4 : 0,
            removedRatio: nextWasCompacted ? nextRemovedRatio : 0,
            wasCompacted: nextWasCompacted,
        )
    }
}

// MARK: - Mock Capture Context Resolver

@MainActor
final class MockCaptureContextResolver: CaptureContextResolving {
    var resolvedContext: ResolvedCaptureContext?
    var detectedMeetingCandidate: ResolvedCaptureContext?

    func resolveContext(for purpose: CapturePurpose, activeContext: ActiveAppContext?) -> ResolvedCaptureContext {
        if let resolvedContext {
            return resolvedContext
        }

        return ResolvedCaptureContext(
            purpose: purpose,
            meetingApp: purpose == .meeting ? .zoom : .unknown,
            appBundleIdentifier: activeContext?.bundleIdentifier,
            appDisplayName: activeContext?.name,
            activeBrowserURL: nil,
            matchedWebMeetingTargetID: nil,
            matchedWebContextTargetID: nil,
            matchedDictationRuleBundleID: nil,
            isKnownMeetingCandidate: purpose == .meeting,
        )
    }

    func detectMeetingCandidate(in runningApps: [NSRunningApplication]) -> ResolvedCaptureContext? {
        detectedMeetingCandidate
    }
}

@MainActor
final class MockMeetingRepository: MeetingRepository {
    var meetingsByID: [UUID: CaptureSessionEntity] = [:]
    var updatedMeetings: [CaptureSessionEntity] = []
    var deletedMeetingIDs: [UUID] = []
    var onUpdateMeeting: ((CaptureSessionEntity) -> Void)?
    var onSaveMeeting: ((CaptureSessionEntity) -> Void)?

    func saveMeeting(_ meeting: CaptureSessionEntity) async throws {
        meetingsByID[meeting.id] = meeting
        onSaveMeeting?(meeting)
    }

    func fetchMeeting(by id: UUID) async throws -> CaptureSessionEntity? {
        meetingsByID[id]
    }

    func fetchAllMeetings() async throws -> [CaptureSessionEntity] {
        Array(meetingsByID.values)
    }

    func deleteMeeting(by id: UUID) async throws {
        meetingsByID[id] = nil
        deletedMeetingIDs.append(id)
    }

    func updateMeeting(_ meeting: CaptureSessionEntity) async throws {
        meetingsByID[meeting.id] = meeting
        updatedMeetings.append(meeting)
        onUpdateMeeting?(meeting)
    }
}

// MARK: - Mock Notification Service

class MockNotificationService: NotificationServiceProtocol {
    var requestAuthorizationCalled = false
    var showRecordingStartedCalled = false
    var showRecordingStoppedCalled = false
    var showTranscriptionCompletedCalled = false
    var showTranscriptionFailedCalled = false

    var pendingNotifications: [String] = []
    var sentNotifications: [(title: String, body: String)] = []

    func requestAuthorization() {
        requestAuthorizationCalled = true
    }

    func showRecordingStarted() {
        showRecordingStartedCalled = true
        pendingNotifications.append("recordingStarted")
    }

    func showRecordingStopped() {
        showRecordingStoppedCalled = true
        pendingNotifications.append("recordingStopped")
    }

    func showTranscriptionCompleted() {
        showTranscriptionCompletedCalled = true
        pendingNotifications.append("transcriptionCompleted")
    }

    func showTranscriptionFailed() {
        showTranscriptionFailedCalled = true
        pendingNotifications.append("transcriptionFailed")
    }

    func sendNotification(title: String, body: String) {
        sentNotifications.append((title, body))
    }
}

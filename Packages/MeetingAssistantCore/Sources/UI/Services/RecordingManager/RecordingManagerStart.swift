import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

// swiftlint:disable function_body_length

// MARK: - Recording Start

public extension RecordingManager {
    func startCapture(purpose: CapturePurpose) async {
        let triggerLabel = purpose == .dictation ? "recording.start.dictation" : "recording.start.meeting"
        await startCapture(purpose: purpose, requestedAt: Date(), triggerLabel: triggerLabel)
    }

    func startCapture(
        purpose: CapturePurpose,
        requestedAt: Date,
        triggerLabel: String,
    ) async {
        await startCapture(
            purpose: purpose,
            source: source(for: purpose),
            requestedAt: requestedAt,
            triggerLabel: triggerLabel,
        )
    }

    /// Start recording audio for a meeting.
    /// - Parameters:
    ///   - source: The audio source to record.
    func startRecording(source: RecordingSource = .microphone) async {
        await startCapture(
            purpose: normalizedCapturePurpose(for: source),
            source: normalizedRecordingSource(for: source),
            requestedAt: Date(),
            triggerLabel: "recording.start.default",
        )
    }

    func startCapture(
        purpose: CapturePurpose,
        source: RecordingSource,
        requestedAt: Date,
        triggerLabel: String,
    ) async {
        cancelAutomaticMeetingRecordingConfirmation()

        guard !isRecording else {
            AppLogger.info("Attempted to start recording but already recording", category: .recordingManager)
            return
        }

        guard !isStartOperationInFlight else { return }
        isStartOperationInFlight = true
        defer { isStartOperationInFlight = false }

        await lifecycleCoordinator.start(
            isRecording: isRecording,
            actions: RecordingLifecycleCoordinator.StartActions(
                beginExclusivity: {
                    let acquired = await RecordingExclusivityCoordinator.shared.beginRecording(mode: self.exclusivityMode(for: purpose))
                    if !acquired {
                        AppLogger.info("Recording start blocked by exclusivity coordinator", category: .recordingManager)
                    }
                    return acquired
                },
                beginState: {
                    self.currentCapturePurpose = purpose
                    self.recordingSource = source
                    self.activePostProcessingKernelMode = purpose.intelligenceKernelMode
                    self.isMeetingMicrophoneEnabled = purpose == .meeting
                    self.dictationSessionOutputLanguageOverride = nil
                    self.refreshPostProcessingReadinessWarning(for: purpose.intelligenceKernelMode)
                    self.activeStartTelemetry = RecordingStartTelemetry(
                        triggerLabel: triggerLabel,
                        source: source,
                        requestedAt: requestedAt,
                        managerEntryAt: Date(),
                    )
                    self.isStartingRecording = true
                },
                prepare: {
                    try await self.prepareAndStartRecording(purpose: purpose, source: source)
                },
                commit: { audioURL in
                    self.commitRecordingStart(audioURL: audioURL, source: source)
                },
            ),
            operations: lifecycleOperations,
            handleFailure: { error in
                await self.handleStartRecordingError(error)
            },
        )
    }

    func noteIndicatorShownForStartIfNeeded() {
        guard var telemetry = activeStartTelemetry else { return }
        guard telemetry.indicatorShownAt == nil else { return }

        let now = Date()
        telemetry.indicatorShownAt = now
        activeStartTelemetry = telemetry

        let requestedToIndicatorMs = now.timeIntervalSince(telemetry.requestedAt) * 1_000
        PerformanceMonitor.shared.reportMetric(
            name: "recording_start_requested_to_indicator_ms",
            value: requestedToIndicatorMs,
            unit: "ms",
        )

        if let recorderStartedAt = telemetry.recorderStartedAt {
            let recorderToIndicatorMs = now.timeIntervalSince(recorderStartedAt) * 1_000
            PerformanceMonitor.shared.reportMetric(
                name: "recording_start_recorder_to_indicator_ms",
                value: recorderToIndicatorMs,
                unit: "ms",
            )
        }

        AppLogger.debug("Recording startup indicator is visible", category: .performance, extra: [
            "trace": telemetry.traceID,
            "trigger": telemetry.triggerLabel,
            "source": telemetry.source.rawValue,
        ])
    }

    func overrideCurrentMeetingType(_ type: MeetingType) {
        guard isRecording, var meeting = currentMeeting else { return }
        meeting.type = type
        currentMeeting = meeting
    }

    func toggleMeetingMicrophone() async {
        await setMeetingMicrophoneEnabled(!isMeetingMicrophoneEnabled)
    }

    func setMeetingMicrophoneEnabled(_ isEnabled: Bool) async {
        guard currentCapturePurpose == .meeting, isRecording || isStartingRecording || isTranscribing else { return }
        isMeetingMicrophoneEnabled = isEnabled

        if let recorder = concreteMicRecorder {
            recorder.setMeetingMicrophoneEnabled(isEnabled)
        }
    }
}

extension RecordingManager {
    private func prepareAndStartRecording(purpose: CapturePurpose, source: RecordingSource) async throws -> URL {
        let initialActiveContext = try? await activeAppContextProvider.fetchActiveAppContext()
        let refreshedActiveContext: ActiveAppContext? = if purpose == .dictation, shouldRefreshContextCapture(initialActiveContext) {
            try? await activeAppContextProvider.fetchActiveAppContext()
        } else {
            nil
        }
        let activeContext = preferredContextForCapture(
            primary: initialActiveContext,
            fallback: refreshedActiveContext,
        )
        let resolvedContext = captureContextResolver.resolveContext(
            for: purpose,
            activeContext: activeContext,
        )
        let meeting = createMeeting(
            type: resolveMeetingType(),
            purpose: purpose,
            resolvedContext: resolvedContext,
        )
        dictationStartBundleIdentifier = purpose == .dictation ? resolvedContext.appBundleIdentifier : nil
        dictationStartURL = purpose == .dictation ? resolvedContext.activeBrowserURL : nil
        currentMeeting = meeting
        currentCapturePurpose = meeting.capturePurpose
        postProcessingContext = nil
        postProcessingContextItems = []
        activeDictationStyleSnapshot = nil
        clearActiveTranscriptionSnapshot()
        restoreMeetingNotesIfNeeded(for: meeting.id)
        isMeetingNotesPanelVisible = false

        if purpose == .dictation {
            let dictationStyle = AppSettingsStore.shared.effectiveDictationStyle(
                bundleIdentifier: resolvedContext.appBundleIdentifier,
                activeURL: resolvedContext.activeBrowserURL,
            )
            activeDictationStyleSnapshot = dictationStyle
            let selectedTextCapture = await contextCaptureService.captureSelectedTextAtDictationStart(
                contextSourcePolicy: dictationStyle.contextSourcePolicy,
            )
            if let selectedTextItem = selectedTextCapture.item {
                postProcessingContextItems = [selectedTextItem]
                postProcessingContext = selectedTextCapture.context
            }
        }

        let settings = AppSettingsStore.shared
        let vocabularySnapshot = VocabularySnapshot.current(from: settings)
        activeVocabularySnapshot = vocabularySnapshot
        let dictationConfiguration = activeDictationStyleSnapshot?.transcriptionConfiguration
        let selection = dictationConfiguration?.selection
            ?? settings.resolvedTranscriptionSelection(for: purpose.transcriptionExecutionMode)
        let inputLanguageCode = dictationConfiguration?.inputLanguageCode
            ?? settings.resolvedTranscriptionInputLanguageCode(for: purpose.transcriptionExecutionMode)
        activeTranscriptionConfiguration = DomainTranscriptionRequestConfiguration(
            providerID: selection.provider.rawValue,
            modelID: selection.selectedModel,
            inputLanguageCode: inputLanguageCode,
            vocabularyHints: vocabularySnapshot.providerHints,
        )

        let operationSnapshot = makeTranscriptionSessionSnapshot(meeting)
        activeUseCaseConfig = operationSnapshot.useCaseConfig
        activeAutoExportSummaries = operationSnapshot.autoExportSummaries
        activeDeliverySettings = operationSnapshot.deliverySettings

        let audioURL = storage.createRecordingURL(for: meeting, type: .merged)
        await setMergedAudioURL(audioURL)
        try await prepareIncrementalDictationSessionIfNeeded(
            meeting: meeting,
            purpose: purpose,
            source: source,
        )
        try await prepareIncrementalMeetingSessionIfNeeded(
            meeting: meeting,
            purpose: purpose,
            source: source,
        )
        try await startRecorder(to: audioURL, source: source)
        // Defer ASR model load until after AVAudioEngine.start so MainActor warmup
        // cannot race the mic recorder critical path.
        await incrementalDictationCoordinator?.beginASRWarmupIfNeeded()

        let recorderStartAt = Date()
        markRecorderStartedAt(recorderStartAt)

        return audioURL
    }

    private func commitRecordingStart(audioURL: URL, source: RecordingSource) {
        guard let meeting = currentMeeting else { return }

        isRecording = true
        isStartingRecording = false
        meetingState = .recording
        currentMeeting?.state = .recording
        currentMeeting?.audioFilePath = audioURL.path
        SoundFeedbackService.shared.playRecordingStartSound()

        enrichMeetingWithCalendarContextAfterRecordingStartIfNeeded(meetingID: meeting.id)
        startContextCaptureAfterRecordingStart(meetingID: meeting.id)

        AppLogger.info("Recording started successfully", category: .recordingManager, extra: [
            "app": meeting.appName,
            "url": audioURL.lastPathComponent,
            "source": source.rawValue,
        ])

        scheduleEagerDictationWarmupIfNeeded(meetingID: meeting.id)
        scheduleDeferredIncrementalWarmupIfNeeded(meetingID: meeting.id)
    }

    private func shouldRefreshContextCapture(_ context: ActiveAppContext?) -> Bool {
        guard let context else { return true }
        return isOwnBundleIdentifier(context.bundleIdentifier)
    }

    private func preferredContextForCapture(
        primary: ActiveAppContext?,
        fallback: ActiveAppContext?,
    ) -> ActiveAppContext? {
        if let primary, !isOwnBundleIdentifier(primary.bundleIdentifier) {
            return primary
        }

        if let fallback, !isOwnBundleIdentifier(fallback.bundleIdentifier) {
            return fallback
        }

        return primary ?? fallback
    }

    private func isOwnBundleIdentifier(_ bundleIdentifier: String) -> Bool {
        let normalized = WebTargetDetection.normalizeBundleIdentifier(bundleIdentifier)
        let appBundleID = WebTargetDetection.normalizeBundleIdentifier(AppIdentity.bundleIdentifier)
        let runtimeBundleID = WebTargetDetection.normalizeBundleIdentifier(Bundle.main.bundleIdentifier ?? "")
        return normalized == appBundleID || (!runtimeBundleID.isEmpty && normalized == runtimeBundleID)
    }

    private func exclusivityMode(for purpose: CapturePurpose) -> RecordingExclusivityCoordinator.RecordingMode {
        switch purpose {
        case .dictation:
            .dictation
        case .meeting:
            .meeting
        }
    }

    private func resolveMeetingType() -> MeetingType {
        let settings = AppSettingsStore.shared
        return settings.meetingTypeAutoDetectEnabled ? .autodetect : .general
    }

    private func createMeeting(
        type: MeetingType,
        purpose: CapturePurpose,
        resolvedContext: ResolvedCaptureContext,
    ) -> Meeting {
        Meeting(
            app: purpose == .dictation ? .unknown : resolvedContext.meetingApp,
            capturePurpose: purpose,
            appBundleIdentifier: resolvedContext.appBundleIdentifier,
            appDisplayName: resolvedContext.appDisplayName,
            type: type,
            state: .idle,
        )
    }

    private func normalizedCapturePurpose(for source: RecordingSource) -> CapturePurpose {
        switch source {
        case .microphone:
            .dictation
        case .system, .all:
            .meeting
        }
    }

    private func normalizedRecordingSource(for source: RecordingSource) -> RecordingSource {
        switch source {
        case .microphone:
            .microphone
        case .system, .all:
            .all
        }
    }

    private func source(for purpose: CapturePurpose) -> RecordingSource {
        switch purpose {
        case .dictation:
            .microphone
        case .meeting:
            .all
        }
    }

    private func startRecorder(to url: URL, source: RecordingSource) async throws {
        AppLogger.debug("Starting recorder", category: .recordingManager, extra: [
            "url": url.path,
            "source": source.rawValue,
        ])

        if let recorder = concreteMicRecorder {
            try await recorder.startRecording(to: url, source: source, retryCount: 0)
        } else {
            try await micRecorder.startRecording(to: url, retryCount: 0)
        }
    }

    private func handleStartRecordingError(_ error: Error) async {
        AppLogger.fault(
            "CRITICAL: Failed to start recording",
            category: .recordingManager,
            error: error,
            extra: ["state": "start_failed"],
        )
    }

    private func enrichMeetingWithCalendarContextAfterRecordingStartIfNeeded(meetingID: UUID) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let currentMeeting, currentMeeting.id == meetingID else { return }

            let enrichedMeeting = await applyAutomaticCalendarEventIfAvailable(to: currentMeeting)
            guard let latestMeeting = self.currentMeeting, latestMeeting.id == meetingID else { return }

            let updatedMeeting = meetingApplyingCalendarEvent(
                enrichedMeeting.linkedCalendarEvent,
                to: latestMeeting,
                clearTitleWhenRemoving: false,
            )
            self.currentMeeting = updatedMeeting
            synchronizeMeetingNotesWithLinkedCalendarEventIfNeeded(
                linkedEventIdentifier: updatedMeeting.linkedCalendarEvent?.eventIdentifier,
            )
        }
    }
}

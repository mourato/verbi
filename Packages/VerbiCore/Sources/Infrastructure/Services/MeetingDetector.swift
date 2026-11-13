import AppKit
import Combine
import Foundation
import os.log
import VerbiCoreCommon
import VerbiCoreDomain

/// Service for detecting active meetings from supported apps and media activity.
@MainActor
public class MeetingDetector: ObservableObject {
    public static let shared = MeetingDetector()

    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "MeetingDetector")
    private let captureContextResolver: any CaptureContextResolving
    private let mediaActivityProvider: any MeetingMediaActivityProviding
    private let audioProcessProvider: (any MeetingAudioProcessProviding)?

    @Published public private(set) var detectedMeeting: CaptureOrigin?
    @Published public private(set) var detectedContext: ResolvedCaptureContext?
    @Published public private(set) var mediaActivity = MeetingMediaActivity()
    @Published public private(set) var detectionSignals: MeetingDetectionSignals?
    @Published private(set) var isMonitoring = false

    private var monitoringTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// Poll interval in seconds
    private let pollInterval: TimeInterval = 10.0
    private let pollTimerTolerance: TimeInterval = 2.0

    /// How long a detected meeting survives without any signal. A tab switch or a short
    /// microphone gap must not end it; only a sustained absence does.
    private let detectionLossGracePeriod: TimeInterval
    private let now: @MainActor () -> Date
    private var detectionLostAt: Date?

    public init(
        captureContextResolver: any CaptureContextResolving = CaptureContextResolver.shared,
        mediaActivityProvider: any MeetingMediaActivityProviding = SystemMeetingMediaActivityProvider(),
        audioProcessProvider: (any MeetingAudioProcessProviding)? = nil,
        detectionLossGracePeriod: TimeInterval = 30,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.captureContextResolver = captureContextResolver
        self.mediaActivityProvider = mediaActivityProvider
        self.detectionLossGracePeriod = detectionLossGracePeriod
        self.now = now
        let processProvider = audioProcessProvider ?? (mediaActivityProvider as? SystemMeetingMediaActivityProvider)?.audioProcessProvider ?? CoreAudioMeetingProcessProvider.shared
        self.audioProcessProvider = processProvider
        let currentActivity = mediaActivityProvider.currentActivity()
        mediaActivity = currentActivity
        detectionSignals = currentActivity.signals
        setupAppNotifications()
        setupAudioProcessListener()
    }

    /// Start monitoring for meeting apps.
    public func startMonitoring() {
        guard !isMonitoring else { return }

        logger.info("Starting meeting detection monitoring")
        isMonitoring = true

        // Initial check
        checkForMeetings()

        // Periodic polling
        monitoringTimer = Timer.scheduledTimer(
            withTimeInterval: pollInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkForMeetings()
            }
        }
        monitoringTimer?.tolerance = pollTimerTolerance
    }

    /// Stop monitoring for meeting apps.
    public func stopMonitoring() {
        logger.info("Stopping meeting detection monitoring")
        isMonitoring = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        detectedMeeting = nil
        detectedContext = nil
        detectionSignals = nil
        detectionLostAt = nil
    }

    /// Check currently running apps for active meetings.
    func checkForMeetings() {
        refreshMediaActivity()
        detectionSignals = mediaActivity.signals
        let runningApps = NSWorkspace.shared.runningApplications

        // Once a meeting is detected, its app plus active media keep it alive. The browser URL
        // only identifies a meeting at the start; the user may switch tabs during the call.
        if let detectedContext,
           isStillPresent(detectedContext, runningBundleIdentifiers: runningApps.compactMap(\.bundleIdentifier))
        {
            detectionLostAt = nil
            return
        }

        if let resolvedContext = captureContextResolver.detectMeetingCandidate(in: runningApps) {
            detectionLostAt = nil
            if let detectedContext, detectedContext.isSameMeeting(as: resolvedContext) {
                return
            }
            if let bundleIdentifier = resolvedContext.appBundleIdentifier {
                logger.info("Detected meeting candidate: \(resolvedContext.meetingApp.displayName) [\(bundleIdentifier)]")
            } else {
                logger.info("Detected meeting candidate: \(resolvedContext.meetingApp.displayName)")
            }
            detectedContext = resolvedContext
            detectedMeeting = resolvedContext.meetingApp
            return
        }

        guard detectedMeeting != nil || detectedContext != nil else { return }

        let lostAt = detectionLostAt ?? now()
        detectionLostAt = lostAt
        guard now().timeIntervalSince(lostAt) >= detectionLossGracePeriod else { return }

        logger.info("Meeting ended")
        detectionLostAt = nil
        detectedMeeting = nil
        detectedContext = nil
    }

    private func isStillPresent(_ context: ResolvedCaptureContext, runningBundleIdentifiers: [String]) -> Bool {
        guard mediaActivity.isActive, let bundleIdentifier = context.appBundleIdentifier else { return false }
        return runningBundleIdentifiers.contains { $0.caseInsensitiveCompare(bundleIdentifier) == .orderedSame }
    }

    @discardableResult
    public func refreshMediaActivity() -> MeetingMediaActivity {
        let activity = mediaActivityProvider.currentActivity()
        if mediaActivity != activity {
            logger.debug(
                "Meeting media activity changed: microphone=\(activity.microphoneInUseByAnotherApplication), camera=\(activity.cameraInUseByAnotherApplication), attribution=\(activity.signals.attribution.rawValue)"
            )
            mediaActivity = activity
            detectionSignals = activity.signals
        }
        return activity
    }

    /// Setup notifications for app launches/terminations.
    private func setupAppNotifications() {
        let workspace = NSWorkspace.shared

        // Ignore Verbi's own lifecycle notifications to avoid work during teardown.
        let handleWorkspaceAppChange: @MainActor @Sendable (NSRunningApplication, String) -> Void = { [weak self] app, eventName in
            guard let self,
                  app.bundleIdentifier != AppIdentity.bundleIdentifier
            else {
                return
            }

            logger.debug("App \(eventName): \(app.bundleIdentifier ?? "unknown")")

            guard isMonitoring else { return }
            checkForMeetings()
        }

        workspace.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .sink { notification in
                let appInfo = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                guard let app = appInfo as? NSRunningApplication else { return }
                Task { @MainActor in
                    handleWorkspaceAppChange(app, "launched")
                }
            }
            .store(in: &cancellables)

        workspace.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .sink { notification in
                let appInfo = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                guard let app = appInfo as? NSRunningApplication else { return }
                Task { @MainActor in
                    handleWorkspaceAppChange(app, "terminated")
                }
            }
            .store(in: &cancellables)
    }

    private func setupAudioProcessListener() {
        audioProcessProvider?.onProcessActivityChanged = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, isMonitoring else { return }
                logger.debug("Audio process activity changed, checking for meetings")
                checkForMeetings()
            }
        }
    }
}

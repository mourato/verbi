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
    @Published public private(set) var isMeetingSignalPresent = false
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
    private let runningApplications: @MainActor () -> [NSRunningApplication]
    private var detectionLostAt: Date?

    /// True while the detected meeting has a live signal. False during the loss grace period,
    /// when the meeting is still shown but must not start a recording on its own.
    public init(
        captureContextResolver: any CaptureContextResolving = CaptureContextResolver.shared,
        mediaActivityProvider: any MeetingMediaActivityProviding = SystemMeetingMediaActivityProvider(),
        audioProcessProvider: (any MeetingAudioProcessProviding)? = nil,
        detectionLossGracePeriod: TimeInterval = 30,
        now: @escaping @MainActor () -> Date = Date.init,
        runningApplications: @escaping @MainActor () -> [NSRunningApplication] = { NSWorkspace.shared.runningApplications }
    ) {
        self.captureContextResolver = captureContextResolver
        self.mediaActivityProvider = mediaActivityProvider
        self.detectionLossGracePeriod = detectionLossGracePeriod
        self.now = now
        self.runningApplications = runningApplications
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
            Task { @MainActor [weak self] in
                guard let self, isMonitoring else { return }
                checkForMeetings()
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
        isMeetingSignalPresent = false
    }

    /// Check currently running apps for active meetings.
    func checkForMeetings() {
        refreshMediaActivity()
        detectionSignals = mediaActivity.signals
        let runningApps = runningApplications()
        let resolvedContext = captureContextResolver.detectMeetingCandidate(in: runningApps)
        // A meeting that lost its signal has ended for practical purposes: when the same app
        // comes back with a different meeting (a new Meet room), that is a new meeting.
        let wasLost = detectionLostAt != nil

        // The browser URL identifies a meeting only at its start; the user may switch tabs
        // during the call. While the meeting app still holds the microphone, the meeting stays,
        // and only another app that also holds the microphone may replace it.
        if let detectedContext,
           isStillPresent(detectedContext, runningBundleIdentifiers: runningApps.compactMap(\.bundleIdentifier))
        {
            detectionLostAt = nil
            isMeetingSignalPresent = true
            if let resolvedContext,
               canReplace(detectedContext, with: resolvedContext)
               || (wasLost && isNewMeetingInSameApp(detectedContext, resolvedContext))
            {
                publish(resolvedContext)
            }
            return
        }

        if let resolvedContext {
            detectionLostAt = nil
            isMeetingSignalPresent = true
            if let detectedContext, detectedContext.isSameMeeting(as: resolvedContext) {
                return
            }
            publish(resolvedContext)
            return
        }

        guard detectedContext != nil else {
            isMeetingSignalPresent = false
            return
        }

        let lostAt = detectionLostAt ?? now()
        detectionLostAt = lostAt
        isMeetingSignalPresent = false
        guard now().timeIntervalSince(lostAt) >= detectionLossGracePeriod else { return }

        logger.info("Meeting ended")
        detectionLostAt = nil
        detectedMeeting = nil
        detectedContext = nil
        isMeetingSignalPresent = false
    }

    private func publish(_ context: ResolvedCaptureContext) {
        if let bundleIdentifier = context.appBundleIdentifier {
            logger.info("Detected meeting candidate: \(context.meetingApp.displayName) [\(bundleIdentifier)]")
        } else {
            logger.info("Detected meeting candidate: \(context.meetingApp.displayName)")
        }
        detectedContext = context
        detectedMeeting = context.meetingApp
        isMeetingSignalPresent = true
    }

    /// A present meeting yields only to a different app that holds the microphone itself.
    /// A weaker candidate (an app that is merely running) or another room in the same browser
    /// must not replace a call that is still going on.
    private func canReplace(_ current: ResolvedCaptureContext, with candidate: ResolvedCaptureContext) -> Bool {
        guard let candidateBundle = candidate.appBundleIdentifier?.lowercased(),
              candidateBundle != current.appBundleIdentifier?.lowercased()
        else {
            return false
        }
        return holdsMicrophone(candidateBundle)
    }

    private func isNewMeetingInSameApp(_ current: ResolvedCaptureContext, _ candidate: ResolvedCaptureContext) -> Bool {
        current.appBundleIdentifier?.lowercased() == candidate.appBundleIdentifier?.lowercased()
            && !current.isSameMeeting(as: candidate)
    }

    private func isStillPresent(_ context: ResolvedCaptureContext, runningBundleIdentifiers: [String]) -> Bool {
        guard mediaActivity.isActive, let bundleIdentifier = context.appBundleIdentifier?.lowercased() else { return false }

        // When the microphone owners are known, the meeting app itself must be one of them.
        if mediaActivity.signals.attribution == .resolved {
            return holdsMicrophone(bundleIdentifier)
        }

        return runningBundleIdentifiers.contains { $0.lowercased() == bundleIdentifier }
    }

    /// True when the app, or a process that captures audio on its behalf, holds the microphone.
    /// Chromium browsers capture in `<bundle>.helper` processes; Safari captures in WebKit's
    /// shared processes (`com.apple.WebKit.*`).
    private func holdsMicrophone(_ bundleIdentifier: String) -> Bool {
        guard mediaActivity.signals.attribution == .resolved else { return false }
        return mediaActivity.signals.activeCallBundleIdentifiers.contains { owner in
            let owner = owner.lowercased()
            if owner == bundleIdentifier || owner.hasPrefix(bundleIdentifier + ".") {
                return true
            }
            return bundleIdentifier == "com.apple.safari" && owner.hasPrefix("com.apple.webkit.")
        }
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

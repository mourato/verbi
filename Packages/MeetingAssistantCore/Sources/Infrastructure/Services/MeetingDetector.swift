import AppKit
import Combine
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import os.log

/// Service for detecting active meetings from supported apps and media activity.
@MainActor
public class MeetingDetector: ObservableObject {
    public static let shared = MeetingDetector()

    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "MeetingDetector")
    private let captureContextResolver: any CaptureContextResolving
    private let mediaActivityProvider: any MeetingMediaActivityProviding

    @Published public private(set) var detectedMeeting: MeetingApp?
    @Published public private(set) var detectedContext: ResolvedCaptureContext?
    @Published public private(set) var mediaActivity = MeetingMediaActivity()
    @Published private(set) var isMonitoring = false

    private var monitoringTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// Poll interval in seconds
    private let pollInterval: TimeInterval = 10.0
    private let pollTimerTolerance: TimeInterval = 2.0

    public init(
        captureContextResolver: any CaptureContextResolving = CaptureContextResolver.shared,
        mediaActivityProvider: any MeetingMediaActivityProviding = SystemMeetingMediaActivityProvider(),
    ) {
        self.captureContextResolver = captureContextResolver
        self.mediaActivityProvider = mediaActivityProvider
        mediaActivity = mediaActivityProvider.currentActivity()
        setupAppNotifications()
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
            repeats: true,
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
    }

    /// Check currently running apps for active meetings.
    private func checkForMeetings() {
        refreshMediaActivity()
        let runningApps = NSWorkspace.shared.runningApplications
        let resolvedContext = captureContextResolver.detectMeetingCandidate(in: runningApps)

        if let resolvedContext {
            if detectedContext != resolvedContext || detectedMeeting != resolvedContext.meetingApp {
                if let bundleIdentifier = resolvedContext.appBundleIdentifier {
                    logger.info("Detected meeting candidate: \(resolvedContext.meetingApp.displayName) [\(bundleIdentifier)]")
                } else {
                    logger.info("Detected meeting candidate: \(resolvedContext.meetingApp.displayName)")
                }
                detectedContext = resolvedContext
                detectedMeeting = resolvedContext.meetingApp
            }
            return
        }

        if detectedMeeting != nil || detectedContext != nil {
            logger.info("Meeting ended")
            detectedMeeting = nil
            detectedContext = nil
        }
    }

    @discardableResult
    public func refreshMediaActivity() -> MeetingMediaActivity {
        let activity = mediaActivityProvider.currentActivity()
        if mediaActivity != activity {
            logger.debug(
                "Meeting media activity changed: microphone=\(activity.microphoneInUseByAnotherApplication), camera=\(activity.cameraInUseByAnotherApplication)",
            )
            mediaActivity = activity
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
}

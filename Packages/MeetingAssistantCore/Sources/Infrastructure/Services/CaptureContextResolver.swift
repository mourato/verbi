import AppKit
import Foundation
import MeetingAssistantCoreDomain

public struct ResolvedCaptureContext: Sendable, Equatable {
    public let purpose: CapturePurpose
    public let meetingApp: MeetingApp
    public let appBundleIdentifier: String?
    public let appDisplayName: String?
    public let activeBrowserURL: URL?
    public let matchedWebMeetingTargetID: UUID?
    public let matchedWebContextTargetID: UUID?
    public let matchedDictationRuleBundleID: String?
    public let isKnownMeetingCandidate: Bool

    public init(
        purpose: CapturePurpose,
        meetingApp: MeetingApp = .unknown,
        appBundleIdentifier: String? = nil,
        appDisplayName: String? = nil,
        activeBrowserURL: URL? = nil,
        matchedWebMeetingTargetID: UUID? = nil,
        matchedWebContextTargetID: UUID? = nil,
        matchedDictationRuleBundleID: String? = nil,
        isKnownMeetingCandidate: Bool = false
    ) {
        self.purpose = purpose
        self.meetingApp = meetingApp
        self.appBundleIdentifier = appBundleIdentifier
        self.appDisplayName = appDisplayName
        self.activeBrowserURL = activeBrowserURL
        self.matchedWebMeetingTargetID = matchedWebMeetingTargetID
        self.matchedWebContextTargetID = matchedWebContextTargetID
        self.matchedDictationRuleBundleID = matchedDictationRuleBundleID
        self.isKnownMeetingCandidate = isKnownMeetingCandidate
    }
}

@MainActor
public protocol CaptureContextResolving: Sendable {
    func resolveContext(for purpose: CapturePurpose, activeContext: ActiveAppContext?) -> ResolvedCaptureContext
    func detectMeetingCandidate(in runningApps: [NSRunningApplication]) -> ResolvedCaptureContext?
}

@MainActor
public final class CaptureContextResolver: CaptureContextResolving {
    public static let shared = CaptureContextResolver()

    private let settings: AppSettingsStore
    private var browserProviders: [String: BrowserActiveTabURLProviding]
    private let mediaActivityProvider: any MeetingMediaActivityProviding

    public init(
        settings: AppSettingsStore = .shared,
        mediaActivityProvider: any MeetingMediaActivityProviding = SystemMeetingMediaActivityProvider()
    ) {
        self.settings = settings
        browserProviders = BrowserProviderRegistry.defaultProviders()
        self.mediaActivityProvider = mediaActivityProvider
    }

    public func resolveContext(for purpose: CapturePurpose, activeContext: ActiveAppContext?) -> ResolvedCaptureContext {
        let bundleIdentifier = activeContext?.bundleIdentifier
        let trimmedDisplayName = activeContext?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = (trimmedDisplayName?.isEmpty == false) ? trimmedDisplayName : nil
        let normalizedBundleIdentifier = bundleIdentifier.map(WebTargetDetection.normalizeBundleIdentifier)
        let activeURL = activeBrowserURL(for: bundleIdentifier)

        switch purpose {
        case .dictation:
            let matchedWebContextTarget = matchWebContextTarget(
                bundleIdentifier: normalizedBundleIdentifier,
                activeURL: activeURL
            )
            let matchedDictationRule = matchDictationAppRule(bundleIdentifier: normalizedBundleIdentifier)

            return ResolvedCaptureContext(
                purpose: purpose,
                appBundleIdentifier: bundleIdentifier,
                appDisplayName: displayName,
                activeBrowserURL: activeURL,
                matchedWebContextTargetID: matchedWebContextTarget?.id,
                matchedDictationRuleBundleID: matchedDictationRule?.bundleIdentifier
            )
        case .meeting:
            if let normalizedBundleIdentifier,
               let matchedWebMeetingTarget = matchWebMeetingTarget(
                   bundleIdentifier: normalizedBundleIdentifier,
                   activeURL: activeURL
               )
            {
                return ResolvedCaptureContext(
                    purpose: purpose,
                    meetingApp: matchedWebMeetingTarget.app,
                    appBundleIdentifier: bundleIdentifier,
                    appDisplayName: displayName,
                    activeBrowserURL: activeURL,
                    matchedWebMeetingTargetID: matchedWebMeetingTarget.id,
                    isKnownMeetingCandidate: true
                )
            }

            if let normalizedBundleIdentifier,
               let meetingApp = meetingApp(for: normalizedBundleIdentifier),
               meetingApp != .googleMeet
            {
                return ResolvedCaptureContext(
                    purpose: purpose,
                    meetingApp: meetingApp,
                    appBundleIdentifier: bundleIdentifier,
                    appDisplayName: displayName,
                    activeBrowserURL: activeURL,
                    isKnownMeetingCandidate: true
                )
            }

            if let normalizedBundleIdentifier,
               monitoredMeetingBundleIdentifiers().contains(normalizedBundleIdentifier),
               !BrowserProviderRegistry.isLikelyBrowserBundleIdentifier(normalizedBundleIdentifier)
            {
                return ResolvedCaptureContext(
                    purpose: purpose,
                    appBundleIdentifier: bundleIdentifier,
                    appDisplayName: displayName,
                    activeBrowserURL: activeURL,
                    isKnownMeetingCandidate: true
                )
            }

            return ResolvedCaptureContext(
                purpose: purpose,
                appBundleIdentifier: bundleIdentifier,
                appDisplayName: displayName,
                activeBrowserURL: activeURL
            )
        }
    }

    public func detectMeetingCandidate(in runningApps: [NSRunningApplication]) -> ResolvedCaptureContext? {
        guard mediaActivityProvider.currentActivity().isActive else { return nil }

        let monitoredBundleIdentifiers = monitoredMeetingBundleIdentifiers()

        if let webMatch = detectWebMeeting(in: runningApps, monitoredBundleIdentifiers: monitoredBundleIdentifiers) {
            return webMatch
        }

        for meetingApp in MeetingApp.allCases where shouldMonitor(app: meetingApp, monitoredBundleIdentifiers: monitoredBundleIdentifiers) {
            if let runningApp = activeMeetingApp(meetingApp, in: runningApps) {
                return ResolvedCaptureContext(
                    purpose: .meeting,
                    meetingApp: meetingApp,
                    appBundleIdentifier: runningApp.bundleIdentifier,
                    appDisplayName: runningApp.localizedName,
                    isKnownMeetingCandidate: true
                )
            }
        }

        if let runningApp = firstCustomMonitoredApp(in: runningApps, monitoredBundleIdentifiers: monitoredBundleIdentifiers) {
            return ResolvedCaptureContext(
                purpose: .meeting,
                appBundleIdentifier: runningApp.bundleIdentifier,
                appDisplayName: runningApp.localizedName,
                isKnownMeetingCandidate: true
            )
        }

        return nil
    }

    private func matchDictationAppRule(bundleIdentifier: String?) -> DictationAppRule? {
        guard let bundleIdentifier else { return nil }
        return settings.dictationAppRules.first {
            WebTargetDetection.normalizeBundleIdentifier($0.bundleIdentifier) == bundleIdentifier
        }
    }

    private func matchWebContextTarget(bundleIdentifier: String?, activeURL: URL?) -> WebContextTarget? {
        guard let bundleIdentifier else { return nil }
        let webTargets = settings.markdownWebTargets
        guard !webTargets.isEmpty else { return nil }

        if let activeURL {
            return WebTargetDetection.matchTarget(
                for: activeURL,
                bundleIdentifier: bundleIdentifier,
                targets: webTargets,
                fallbackBrowserBundleIdentifiers: settings.effectiveWebTargetBrowserBundleIdentifiers
            )
        }

        return WebTargetDetection.matchTargetByWindowTitle(
            bundleIdentifier: bundleIdentifier,
            targets: webTargets,
            fallbackBrowserBundleIdentifiers: settings.effectiveWebTargetBrowserBundleIdentifiers
        )
    }

    private func matchWebMeetingTarget(bundleIdentifier: String, activeURL: URL?) -> WebMeetingTarget? {
        let meetingTargets = settings.webMeetingTargets
        guard !meetingTargets.isEmpty, let activeURL else { return nil }

        return WebTargetDetection.matchTarget(
            for: activeURL,
            bundleIdentifier: bundleIdentifier,
            targets: meetingTargets,
            fallbackBrowserBundleIdentifiers: settings.effectiveWebTargetBrowserBundleIdentifiers
        )
    }

    private func detectWebMeeting(
        in runningApps: [NSRunningApplication],
        monitoredBundleIdentifiers: Set<String>
    ) -> ResolvedCaptureContext? {
        let meetingTargets = settings.webMeetingTargets
        let autoStartTargets = settings.markdownWebTargets.filter(\.autoStartMeetingRecording)
        guard !meetingTargets.isEmpty || !autoStartTargets.isEmpty else { return nil }

        let fallbackBrowsers = settings.effectiveWebTargetBrowserBundleIdentifiers
        let configuredBrowsers = Set(fallbackBrowsers.map(WebTargetDetection.normalizeBundleIdentifier))
        let monitoredWebBundles = monitoredBundleIdentifiers.union(configuredBrowsers)

        for runningApp in runningApps {
            guard let bundleId = runningApp.bundleIdentifier else { continue }
            let normalizedBundleId = WebTargetDetection.normalizeBundleIdentifier(bundleId)
            guard monitoredWebBundles.contains(normalizedBundleId) else { continue }

            let activeURL = activeBrowserURL(for: bundleId)

            if let activeURL,
               let match = WebTargetDetection.matchTarget(
                   for: activeURL,
                   bundleIdentifier: normalizedBundleId,
                   targets: meetingTargets,
                   fallbackBrowserBundleIdentifiers: fallbackBrowsers
               )
            {
                return ResolvedCaptureContext(
                    purpose: .meeting,
                    meetingApp: match.app,
                    appBundleIdentifier: bundleId,
                    appDisplayName: runningApp.localizedName,
                    activeBrowserURL: activeURL,
                    matchedWebMeetingTargetID: match.id,
                    isKnownMeetingCandidate: true
                )
            }

            if let activeURL,
               WebTargetDetection.matchTarget(
                   for: activeURL,
                   bundleIdentifier: normalizedBundleId,
                   targets: autoStartTargets,
                   fallbackBrowserBundleIdentifiers: fallbackBrowsers
               ) != nil
            {
                return ResolvedCaptureContext(
                    purpose: .meeting,
                    appBundleIdentifier: bundleId,
                    appDisplayName: runningApp.localizedName,
                    activeBrowserURL: activeURL,
                    isKnownMeetingCandidate: true
                )
            }
        }

        return nil
    }

    private func activeBrowserURL(for bundleIdentifier: String?) -> URL? {
        guard let bundleIdentifier else { return nil }
        let normalizedBundleIdentifier = WebTargetDetection.normalizeBundleIdentifier(bundleIdentifier)

        if let provider = browserProviders[normalizedBundleIdentifier] {
            return provider.activeTabURL()
        }

        guard let provider = BrowserProviderRegistry.provider(for: bundleIdentifier) else {
            return nil
        }

        browserProviders[normalizedBundleIdentifier] = provider
        return provider.activeTabURL()
    }

    private func monitoredMeetingBundleIdentifiers() -> Set<String> {
        Set(settings.monitoredMeetingBundleIdentifiers.map(WebTargetDetection.normalizeBundleIdentifier))
    }

    private func meetingApp(for normalizedBundleIdentifier: String) -> MeetingApp? {
        MeetingApp.allCases.first { app in
            app.bundleIdentifiers.contains { WebTargetDetection.normalizeBundleIdentifier($0) == normalizedBundleIdentifier }
        }
    }

    private func shouldMonitor(app: MeetingApp, monitoredBundleIdentifiers: Set<String>) -> Bool {
        guard !app.bundleIdentifiers.isEmpty else { return false }
        return app.bundleIdentifiers.contains { monitoredBundleIdentifiers.contains(WebTargetDetection.normalizeBundleIdentifier($0)) }
    }

    private func activeMeetingApp(_ app: MeetingApp, in runningApps: [NSRunningApplication]) -> NSRunningApplication? {
        let matchingApps = runningApps.filter { runningApp in
            guard let bundleId = runningApp.bundleIdentifier else { return false }
            let normalizedBundleId = WebTargetDetection.normalizeBundleIdentifier(bundleId)
            return app.bundleIdentifiers.contains {
                WebTargetDetection.normalizeBundleIdentifier($0) == normalizedBundleId
            }
        }

        guard let runningApp = matchingApps.first else { return nil }

        if app == .googleMeet {
            return nil
        }

        return runningApp
    }

    private func firstCustomMonitoredApp(
        in runningApps: [NSRunningApplication],
        monitoredBundleIdentifiers: Set<String>
    ) -> NSRunningApplication? {
        for runningApp in runningApps {
            guard let bundleId = runningApp.bundleIdentifier else { continue }
            let normalizedBundleId = WebTargetDetection.normalizeBundleIdentifier(bundleId)
            guard monitoredBundleIdentifiers.contains(normalizedBundleId) else { continue }
            guard !BrowserProviderRegistry.isLikelyBrowserBundleIdentifier(normalizedBundleId) else { continue }
            if meetingApp(for: normalizedBundleId) == nil {
                return runningApp
            }
        }
        return nil
    }
}

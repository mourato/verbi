import AppKit
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain

public struct MeetingReminderScheduleConfiguration: Sendable, Equatable {
    public var remindersEnabled: Bool
    public var leadMinutes: Int
    public var overlayLeadSeconds: Int
    public var overlayEnabled: Bool

    public init(
        remindersEnabled: Bool,
        leadMinutes: Int,
        overlayLeadSeconds: Int,
        overlayEnabled: Bool,
    ) {
        self.remindersEnabled = remindersEnabled
        self.leadMinutes = leadMinutes
        self.overlayLeadSeconds = overlayLeadSeconds
        self.overlayEnabled = overlayEnabled
    }
}

@MainActor
public final class MeetingReminderScheduler {
    public enum SnoozeInterval: Int, CaseIterable, Sendable {
        case one = 1
        case five = 5
        case ten = 10
        case fifteen = 15
    }

    public private(set) var activeAlert: MeetingCalendarEventSnapshot?
    public private(set) var dismissedOccurrenceKeys: Set<String>
    public var onLeadFire: ((MeetingCalendarEventSnapshot) -> Void)?
    public var onScheduleLeadNotification: ((MeetingCalendarEventSnapshot, Date) -> Void)?
    public var onMeetingStartFire: ((MeetingCalendarEventSnapshot) -> Void)?
    public var onCancelLeadNotification: ((MeetingCalendarEventSnapshot) -> Void)?
    public var onWatchdogTick: (() -> Void)?

    private var leadTimers: [String: Timer] = [:]
    private var startTimers: [String: Timer] = [:]
    private var scheduledEffectiveStart: [String: Date] = [:]
    private var scheduledLeadMinutes: Int?
    private var scheduledOverlayLeadSeconds: Int?
    private var snoozeUntil: [String: Date] = [:]
    private var pendingAlerts: [MeetingCalendarEventSnapshot] = []
    private var watchdogTimer: Timer?
    private var activityToken: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private let nowProvider: () -> Date
    private let occurrenceKeyProvider: (MeetingCalendarEventSnapshot) -> String
    private let stalenessGrace: TimeInterval = 10 * 60

    public init(
        dismissedOccurrenceKeys initialDismissedKeys: Set<String> = [],
        now: @escaping () -> Date = Date.init,
        occurrenceKey: @escaping (MeetingCalendarEventSnapshot) -> String = MeetingReminderOccurrenceKey.make(for:),
    ) {
        dismissedOccurrenceKeys = initialDismissedKeys
        nowProvider = now
        occurrenceKeyProvider = occurrenceKey
    }

    isolated deinit {
        watchdogTimer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    public func startReliabilityGuards() {
        if activityToken == nil {
            activityToken = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated],
                reason: "Verbi schedules meeting reminders that must fire on time.",
            )
        }

        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main,
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scheduledEffectiveStart.removeAll()
                }
            }
        }

        startWatchdogIfNeeded()
    }

    public func stopReliabilityGuards() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        if let activityToken {
            ProcessInfo.processInfo.endActivity(activityToken)
            self.activityToken = nil
        }
    }

    public func reschedule(
        events: [MeetingCalendarEventSnapshot],
        configuration: MeetingReminderScheduleConfiguration,
        now: Date? = nil,
    ) {
        guard configuration.remindersEnabled else {
            cancelAllScheduling()
            return
        }

        let currentNow = now ?? nowProvider()
        let currentKeys = Set(events.map(occurrenceKeyProvider))
        purgeStaleScheduling(currentKeys: currentKeys)
        refreshScheduleOffsetsIfNeeded(configuration: configuration)

        for event in events {
            scheduleEvent(event, configuration: configuration, now: currentNow)
        }
    }

    private func purgeStaleScheduling(currentKeys: Set<String>) {
        let droppedKeys = Set(scheduledEffectiveStart.keys).subtracting(currentKeys)

        for (key, timer) in leadTimers where !currentKeys.contains(key) {
            timer.invalidate()
            leadTimers.removeValue(forKey: key)
        }
        for (key, timer) in startTimers where !currentKeys.contains(key) {
            timer.invalidate()
            startTimers.removeValue(forKey: key)
        }

        for key in droppedKeys {
            scheduledEffectiveStart.removeValue(forKey: key)
        }
        for key in Set(snoozeUntil.keys).subtracting(currentKeys) {
            snoozeUntil.removeValue(forKey: key)
        }
        pendingAlerts.removeAll { event in
            !currentKeys.contains(occurrenceKeyProvider(event))
        }
    }

    private func refreshScheduleOffsetsIfNeeded(configuration: MeetingReminderScheduleConfiguration) {
        guard scheduledLeadMinutes != configuration.leadMinutes
            || scheduledOverlayLeadSeconds != configuration.overlayLeadSeconds
        else { return }

        scheduledEffectiveStart.removeAll()
        scheduledLeadMinutes = configuration.leadMinutes
        scheduledOverlayLeadSeconds = configuration.overlayLeadSeconds
    }

    private func scheduleEvent(
        _ event: MeetingCalendarEventSnapshot,
        configuration: MeetingReminderScheduleConfiguration,
        now: Date,
    ) {
        let key = occurrenceKeyProvider(event)
        guard !dismissedOccurrenceKeys.contains(key) else { return }

        let effectiveStart = snoozeUntil[key] ?? event.startDate
        let overlayLeadSeconds = configuration.overlayLeadSeconds

        if configuration.overlayEnabled {
            catchUpMissedOverlayIfNeeded(
                MissedOverlayCatchUpContext(
                    event: event,
                    occurrenceKey: key,
                    effectiveStart: effectiveStart,
                    overlayLeadSeconds: overlayLeadSeconds,
                    now: now,
                    configuration: configuration,
                ),
            )
        }

        if scheduledEffectiveStart[key] == effectiveStart {
            return
        }

        scheduleLead(
            for: event,
            occurrenceKey: key,
            effectiveStart: effectiveStart,
            leadMinutes: configuration.leadMinutes,
            now: now,
        )

        if configuration.overlayEnabled {
            scheduleStart(
                OverlayScheduleContext(
                    event: event,
                    occurrenceKey: key,
                    effectiveStart: effectiveStart,
                    overlayLeadSeconds: overlayLeadSeconds,
                    now: now,
                    configuration: configuration,
                ),
            )
        } else {
            startTimers[key]?.invalidate()
            startTimers.removeValue(forKey: key)
        }

        scheduledEffectiveStart[key] = effectiveStart
    }

    private func catchUpMissedOverlayIfNeeded(_ context: MissedOverlayCatchUpContext) {
        let overlayFireDate = context.effectiveStart.addingTimeInterval(-Double(context.overlayLeadSeconds))
        guard context.effectiveStart < context.event.endDate,
              overlayFireDate <= context.now,
              context.now < context.event.endDate,
              activeAlert == nil,
              !pendingAlerts.contains(where: { occurrenceKeyProvider($0) == context.occurrenceKey })
        else { return }

        fireMeetingStart(context.event, configuration: context.configuration)
    }

    private struct MissedOverlayCatchUpContext {
        let event: MeetingCalendarEventSnapshot
        let occurrenceKey: String
        let effectiveStart: Date
        let overlayLeadSeconds: Int
        let now: Date
        let configuration: MeetingReminderScheduleConfiguration
    }

    private struct OverlayScheduleContext {
        let event: MeetingCalendarEventSnapshot
        let occurrenceKey: String
        let effectiveStart: Date
        let overlayLeadSeconds: Int
        let now: Date
        let configuration: MeetingReminderScheduleConfiguration
    }

    public func dismiss(_ event: MeetingCalendarEventSnapshot) {
        let key = occurrenceKeyProvider(event)
        dismissedOccurrenceKeys.insert(key)
        leadTimers[key]?.invalidate()
        leadTimers.removeValue(forKey: key)
        startTimers[key]?.invalidate()
        startTimers.removeValue(forKey: key)
        snoozeUntil.removeValue(forKey: key)
        scheduledEffectiveStart.removeValue(forKey: key)
        pendingAlerts.removeAll { occurrenceKeyProvider($0) == key }
        onCancelLeadNotification?(event)

        if activeAlert.map(occurrenceKeyProvider) == key {
            activeAlert = nil
            drainPendingAlerts(configuration: nil)
        }
    }

    public func snooze(_ event: MeetingCalendarEventSnapshot, minutes: Int, allEvents: [MeetingCalendarEventSnapshot], configuration: MeetingReminderScheduleConfiguration) {
        let key = occurrenceKeyProvider(event)
        snoozeUntil[key] = nowProvider().addingTimeInterval(Double(minutes * 60))
        scheduledEffectiveStart.removeValue(forKey: key)
        pendingAlerts.removeAll { occurrenceKeyProvider($0) == key }

        if activeAlert.map(occurrenceKeyProvider) == key {
            activeAlert = nil
        }

        reschedule(events: allEvents, configuration: configuration)
    }

    public func snoozeUntilEnd(_ event: MeetingCalendarEventSnapshot, allEvents: [MeetingCalendarEventSnapshot], configuration: MeetingReminderScheduleConfiguration) {
        let key = occurrenceKeyProvider(event)
        snoozeUntil[key] = event.endDate
        scheduledEffectiveStart.removeValue(forKey: key)
        pendingAlerts.removeAll { occurrenceKeyProvider($0) == key }

        if activeAlert.map(occurrenceKeyProvider) == key {
            activeAlert = nil
        }

        reschedule(events: allEvents, configuration: configuration)
    }

    public func overlayDidHide(allEvents: [MeetingCalendarEventSnapshot], configuration: MeetingReminderScheduleConfiguration) {
        activeAlert = nil
        drainPendingAlerts(configuration: configuration, upcomingEvents: allEvents)
    }

    public func cancelAllScheduling() {
        leadTimers.values.forEach { $0.invalidate() }
        startTimers.values.forEach { $0.invalidate() }
        leadTimers.removeAll()
        startTimers.removeAll()
        scheduledEffectiveStart.removeAll()
        snoozeUntil.removeAll()
        pendingAlerts.removeAll()
        activeAlert = nil
    }

    private func startWatchdogIfNeeded() {
        guard watchdogTimer == nil else { return }
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onWatchdogTick?()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdogTimer = timer
    }

    private func scheduleLead(
        for event: MeetingCalendarEventSnapshot,
        occurrenceKey: String,
        effectiveStart: Date,
        leadMinutes: Int,
        now: Date,
    ) {
        leadTimers[occurrenceKey]?.invalidate()
        leadTimers.removeValue(forKey: occurrenceKey)
        onCancelLeadNotification?(event)

        guard leadMinutes > 0 else { return }
        let leadFireDate = effectiveStart.addingTimeInterval(-Double(leadMinutes * 60))
        guard leadFireDate > now else { return }

        onScheduleLeadNotification?(event, leadFireDate)

        let interval = leadFireDate.timeIntervalSince(now)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.leadTimers.removeValue(forKey: occurrenceKey)
                self.onLeadFire?(event)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        leadTimers[occurrenceKey] = timer
    }

    private func scheduleStart(_ context: OverlayScheduleContext) {
        startTimers[context.occurrenceKey]?.invalidate()
        startTimers.removeValue(forKey: context.occurrenceKey)

        if context.effectiveStart >= context.event.endDate {
            return
        }

        let overlayFireDate = context.effectiveStart.addingTimeInterval(-Double(context.overlayLeadSeconds))
        if overlayFireDate <= context.now {
            if activeAlert == nil, context.now < context.event.endDate {
                fireMeetingStart(context.event, configuration: context.configuration)
            }
            return
        }

        let interval = overlayFireDate.timeIntervalSince(context.now)
        let event = context.event
        let configuration = context.configuration
        let occurrenceKey = context.occurrenceKey
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.fireMeetingStart(event, configuration: configuration)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        startTimers[occurrenceKey] = timer
    }

    private func fireMeetingStart(_ event: MeetingCalendarEventSnapshot, configuration: MeetingReminderScheduleConfiguration) {
        let key = occurrenceKeyProvider(event)
        startTimers.removeValue(forKey: key)

        guard !dismissedOccurrenceKeys.contains(key) else { return }

        let effectiveStart = snoozeUntil[key] ?? event.startDate
        let now = nowProvider()
        guard now < event.endDate else { return }
        guard now <= effectiveStart.addingTimeInterval(stalenessGrace) else { return }

        if activeAlert != nil {
            if !pendingAlerts.contains(where: { occurrenceKeyProvider($0) == key }) {
                pendingAlerts.append(event)
            }
            return
        }

        activeAlert = event
        AppLogger.debug("Meeting reminder overlay fire: \(event.trimmedTitle)", category: .recordingManager)
        onMeetingStartFire?(event)
    }

    private func drainPendingAlerts(
        configuration: MeetingReminderScheduleConfiguration?,
        upcomingEvents: [MeetingCalendarEventSnapshot] = [],
    ) {
        let now = nowProvider()
        while let next = pendingAlerts.first {
            pendingAlerts.removeFirst()
            let key = occurrenceKeyProvider(next)
            if dismissedOccurrenceKeys.contains(key) {
                continue
            }
            if now >= next.endDate {
                continue
            }
            if let configuration {
                fireMeetingStart(next, configuration: configuration)
            } else {
                activeAlert = next
                onMeetingStartFire?(next)
            }
            return
        }

        if let configuration, !upcomingEvents.isEmpty {
            reschedule(events: upcomingEvents, configuration: configuration, now: now)
        }
    }
}

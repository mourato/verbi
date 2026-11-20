import Foundation
import VerbiCoreDomain

public extension AppSettingsStore {
    func ignoredCalendarEventIdentifiers() -> Set<String> {
        let occurrenceKeys = activeIgnoredCalendarEventOccurrenceEndDates().keys
        return legacyIgnoredCalendarEventIdentifiers().union(occurrenceKeys)
    }

    func ignoreCalendarEventIdentifier(_ identifier: String) {
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        var identifiers = legacyIgnoredCalendarEventIdentifiers()
        identifiers.insert(normalized)
        save(identifiers, forKey: Keys.ignoredCalendarEventIdentifiers)
    }

    func unignoreCalendarEventIdentifier(_ identifier: String) {
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        var identifiers = legacyIgnoredCalendarEventIdentifiers()
        identifiers.remove(normalized)
        save(identifiers, forKey: Keys.ignoredCalendarEventIdentifiers)
    }

    func ignoreCalendarEventOccurrence(_ event: MeetingCalendarEventSnapshot) {
        var endDates = activeIgnoredCalendarEventOccurrenceEndDates()
        endDates[Self.meetingReminderOccurrenceKey(for: event)] = event.endDate
        save(endDates, forKey: Keys.ignoredCalendarEventOccurrenceEndDates)
    }

    func unignoreCalendarEventOccurrence(_ event: MeetingCalendarEventSnapshot) {
        var endDates = activeIgnoredCalendarEventOccurrenceEndDates()
        endDates[Self.meetingReminderOccurrenceKey(for: event)] = nil
        save(endDates, forKey: Keys.ignoredCalendarEventOccurrenceEndDates)
    }

    private func activeIgnoredCalendarEventOccurrenceEndDates() -> [String: Date] {
        let endDates = Self.loadDecoded([String: Date].self, forKey: Keys.ignoredCalendarEventOccurrenceEndDates) ?? [:]
        let cutoff = Date().addingTimeInterval(-Self.calendarKeyRetentionInterval)
        return endDates.filter { $0.value >= cutoff }
    }

    private func legacyIgnoredCalendarEventIdentifiers() -> Set<String> {
        Self.loadDecoded(Set<String>.self, forKey: Keys.ignoredCalendarEventIdentifiers) ?? []
    }
}

import Foundation
import VerbiCoreDomain

public extension AppSettingsStore {
    /// Legacy raw identifiers (hide whole series) plus unexpired occurrence keys.
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

    /// Hides one occurrence of a recurring event. The entry expires with the occurrence's end date.
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

    /// Drops expired entries on read. The next write persists the pruned map.
    private func activeIgnoredCalendarEventOccurrenceEndDates() -> [String: Date] {
        let endDates = Self.loadDecoded([String: Date].self, forKey: Keys.ignoredCalendarEventOccurrenceEndDates) ?? [:]
        let cutoff = Date().addingTimeInterval(-Self.calendarKeyRetentionInterval)
        return endDates.filter { $0.value >= cutoff }
    }

    private func legacyIgnoredCalendarEventIdentifiers() -> Set<String> {
        Self.loadDecoded(Set<String>.self, forKey: Keys.ignoredCalendarEventIdentifiers) ?? []
    }
}

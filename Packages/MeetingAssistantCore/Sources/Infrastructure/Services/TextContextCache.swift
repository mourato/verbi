import Foundation
import MeetingAssistantCoreDomain

@MainActor
public final class TextContextCache {
    public struct Entry: Sendable {
        public let snapshot: TextContextSnapshot
        public let createdAt: Date

        public init(snapshot: TextContextSnapshot, createdAt: Date) {
            self.snapshot = snapshot
            self.createdAt = createdAt
        }
    }

    private var entries: [String: Entry] = [:]
    private let ttl: TimeInterval
    private let maxEntries: Int

    public init(ttl: TimeInterval = 10, maxEntries: Int = 50) {
        self.ttl = ttl
        self.maxEntries = maxEntries
    }

    public func value(for key: String) -> TextContextSnapshot? {
        purgeExpired()
        return entries[key]?.snapshot
    }

    public func insert(_ snapshot: TextContextSnapshot, for key: String) {
        purgeExpired()
        entries[key] = Entry(snapshot: snapshot, createdAt: Date())
        evictIfNeeded()
    }

    private func purgeExpired() {
        let now = Date()
        entries = entries.filter { now.timeIntervalSince($0.value.createdAt) <= ttl }
    }

    private func evictIfNeeded() {
        guard entries.count > maxEntries else { return }
        let sorted = entries.sorted { $0.value.createdAt < $1.value.createdAt }
        let overflow = entries.count - maxEntries
        for index in 0 ..< overflow {
            entries.removeValue(forKey: sorted[index].key)
        }
    }
}

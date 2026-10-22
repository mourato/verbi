import CoreData
import Foundation
import VerbiCoreDomain

// CoreDataMeetingRepository - Implementação de MeetingRepository usando CoreData
// Thread-safe e isolado do domínio

/// Repositório de reuniões usando CoreData para persistência
public final class CoreDataMeetingRepository: MeetingRepository {
    private let stack: CoreDataStack

    public init(stack: CoreDataStack = .shared) {
        self.stack = stack
    }

    public func saveMeeting(_ meeting: CaptureSessionEntity) async throws {
        await stack.sanitizeMeetingOnlyPresentationDataIfNeeded()
        let sanitizedMeeting = meeting.sanitizedForPersistence()
        try await stack.performBackgroundTask { context in
            _ = CaptureSessionMO.create(from: sanitizedMeeting, in: context)
            try context.save()
        }
    }

    public func fetchMeeting(by id: UUID) async throws -> CaptureSessionEntity? {
        await stack.sanitizeMeetingOnlyPresentationDataIfNeeded()
        return try await stack.performBackgroundTask { context in
            let request = CaptureSessionMO.fetchRequest(for: id)
            let result = try context.fetch(request)
            return result.first?.toDomain().sanitizedForPersistence()
        }
    }

    public func fetchAllMeetings() async throws -> [CaptureSessionEntity] {
        await stack.sanitizeMeetingOnlyPresentationDataIfNeeded()
        return try await stack.performBackgroundTask { context in
            let request = CaptureSessionMO.fetchRequest()
            let results = try context.fetch(request)
            return results.map { $0.toDomain().sanitizedForPersistence() }
        }
    }

    public func deleteMeeting(by id: UUID) async throws {
        try await stack.performBackgroundTask { context in
            let request = CaptureSessionMO.fetchRequest(for: id)
            if let meetingMO = try context.fetch(request).first {
                context.delete(meetingMO)
                try context.save()
            }
        }
    }

    public func updateMeeting(_ meeting: CaptureSessionEntity) async throws {
        await stack.sanitizeMeetingOnlyPresentationDataIfNeeded()
        let sanitizedMeeting = meeting.sanitizedForPersistence()
        try await stack.performBackgroundTask { context in
            let request = CaptureSessionMO.fetchRequest(for: sanitizedMeeting.id)
            if let meetingMO = try context.fetch(request).first {
                meetingMO.update(from: sanitizedMeeting)
                try context.save()
            } else {
                // Se não existe, cria um novo (upsert)
                _ = CaptureSessionMO.create(from: sanitizedMeeting, in: context)
                try context.save()
            }
        }
    }
}

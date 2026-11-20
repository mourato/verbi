import Foundation
import VerbiCoreDomain
import VerbiCoreInfrastructure

public actor MeetingRepositoryAdapter: MeetingRepository {
    private var meetings: [UUID: CaptureSessionEntity] = [:]
    private let storageService: FileSystemStorageService

    public init(storageService: FileSystemStorageService) {
        self.storageService = storageService
    }

    public func saveMeeting(_ meeting: CaptureSessionEntity) throws {
        let sanitizedMeeting = meeting.sanitizedForPersistence()
        meetings[sanitizedMeeting.id] = sanitizedMeeting
    }

    public func fetchMeeting(by id: UUID) throws -> CaptureSessionEntity? {
        meetings[id]?.sanitizedForPersistence()
    }

    public func fetchAllMeetings() throws -> [CaptureSessionEntity] {
        Array(meetings.values)
            .map { $0.sanitizedForPersistence() }
            .sorted { $0.startTime > $1.startTime }
    }

    public func deleteMeeting(by id: UUID) throws {
        meetings.removeValue(forKey: id)
    }

    public func updateMeeting(_ meeting: CaptureSessionEntity) throws {
        let sanitizedMeeting = meeting.sanitizedForPersistence()
        meetings[sanitizedMeeting.id] = sanitizedMeeting
    }
}

import Foundation

public struct MeetingQAModelSelection: Codable, Hashable, Sendable {
    public let providerRawValue: String
    public let modelID: String

    public init(providerRawValue: String, modelID: String) {
        self.providerRawValue = providerRawValue
        self.modelID = modelID
    }
}

public struct MeetingConversationTurn: Codable, Hashable, Sendable {
    public let id: UUID
    public let question: String
    public let response: MeetingQAResponse?
    public let errorMessage: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        question: String,
        response: MeetingQAResponse?,
        errorMessage: String?,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.question = question
        self.response = response
        self.errorMessage = errorMessage
        self.createdAt = createdAt
    }
}

public struct MeetingConversationState: Codable, Hashable, Sendable {
    public let turns: [MeetingConversationTurn]
    public let modelSelection: MeetingQAModelSelection?

    public init(turns: [MeetingConversationTurn], modelSelection: MeetingQAModelSelection?) {
        self.turns = turns
        self.modelSelection = modelSelection
    }
}

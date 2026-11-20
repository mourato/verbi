import Foundation

public struct LLMModel: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var object: String?
    public var created: Int?
    public var ownedBy: String?

    enum CodingKeys: String, CodingKey {
        case id, object, created
        case ownedBy = "owned_by"
    }

    public init(id: String, object: String? = nil, created: Int? = nil, ownedBy: String? = nil) {
        self.id = id
        self.object = object
        self.created = created
        self.ownedBy = ownedBy
    }
}

public struct LLMModelsResponse: Codable, Sendable {
    public var object: String?
    public var data: [LLMModel]
}

import Foundation

// MARK: - LLM Models API Response

/// Represents a single model from an OpenAI-compatible LLM service.
/// Used to populate the model selection picker in settings.
public struct LLMModel: Codable, Identifiable, Equatable, Sendable {
    /// Unique identifier for the model (e.g., "gpt-4o", "claude-3-sonnet").
    public var id: String
    /// Type of object, typically "model".
    public var object: String?
    /// Unix timestamp of when the model was created.
    public var created: Int?
    /// Organization or entity that owns the model.
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

/// Response from the `/models` endpoint of OpenAI-compatible APIs.
/// LiteLLM Proxy and other compatible services use this format.
public struct LLMModelsResponse: Codable, Sendable {
    /// Type of object, typically "list".
    public var object: String?
    /// Array of available models.
    public var data: [LLMModel]
}

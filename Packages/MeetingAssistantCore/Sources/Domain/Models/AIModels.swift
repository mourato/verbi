import Foundation

// MARK: - Shared Models

public struct AIChatMessage: Codable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

// MARK: - OpenAI / Groq / Custom

public struct OpenAIChatRequest: Codable {
    public let model: String
    public let messages: [AIChatMessage]
    public let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
    }

    public init(model: String, messages: [AIChatMessage], maxTokens: Int) {
        self.model = model
        self.messages = messages
        self.maxTokens = maxTokens
    }
}

public struct OpenAIChatResponse: Codable {
    public struct Choice: Codable {
        public struct Message: Codable {
            public let content: String
        }

        public let message: Message
    }

    public let choices: [Choice]
}

public struct OpenAIErrorResponse: Codable {
    public struct ErrorDetail: Codable {
        public let message: String
    }

    public let error: ErrorDetail
}

// MARK: - Anthropic

public struct AnthropicMessageRequest: Codable {
    public let model: String
    public let maxTokens: Int
    public let system: String
    public let messages: [AIChatMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
    }

    public init(model: String, maxTokens: Int, system: String, messages: [AIChatMessage]) {
        self.model = model
        self.maxTokens = maxTokens
        self.system = system
        self.messages = messages
    }
}

public struct AnthropicMessageResponse: Codable {
    public struct Content: Codable {
        public let text: String
    }

    public let content: [Content]
}

public struct AnthropicErrorResponse: Codable {
    public struct ErrorDetail: Codable {
        public let message: String
    }

    public let error: ErrorDetail
}

// MARK: - Google Gemini

public struct GeminiPart: Codable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public struct GeminiContent: Codable, Sendable {
    public let role: String?
    public let parts: [GeminiPart]

    public init(role: String? = nil, parts: [GeminiPart]) {
        self.role = role
        self.parts = parts
    }
}

public struct GeminiSystemInstruction: Codable, Sendable {
    public let parts: [GeminiPart]

    public init(parts: [GeminiPart]) {
        self.parts = parts
    }
}

public struct GeminiGenerationConfig: Codable, Sendable {
    public let maxOutputTokens: Int

    enum CodingKeys: String, CodingKey {
        case maxOutputTokens
    }

    public init(maxOutputTokens: Int) {
        self.maxOutputTokens = maxOutputTokens
    }
}

public struct GeminiGenerateContentRequest: Codable, Sendable {
    public let systemInstruction: GeminiSystemInstruction
    public let contents: [GeminiContent]
    public let generationConfig: GeminiGenerationConfig

    public init(
        systemInstruction: GeminiSystemInstruction,
        contents: [GeminiContent],
        generationConfig: GeminiGenerationConfig
    ) {
        self.systemInstruction = systemInstruction
        self.contents = contents
        self.generationConfig = generationConfig
    }
}

public struct GeminiGenerateContentResponse: Codable, Sendable {
    public struct Candidate: Codable, Sendable {
        public let content: GeminiContent?
    }

    public let candidates: [Candidate]?
}

public struct GeminiErrorResponse: Codable, Sendable {
    public struct ErrorDetail: Codable, Sendable {
        public let message: String
    }

    public let error: ErrorDetail
}

public struct GeminiModelsResponse: Codable, Sendable {
    public struct GeminiModel: Codable, Sendable {
        public let name: String
        public let displayName: String?

        enum CodingKeys: String, CodingKey {
            case name
            case displayName
        }
    }

    public let models: [GeminiModel]
}

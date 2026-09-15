import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

enum ProviderHTTPClientError: LocalizedError {
    case invalidURL
    case noAPIConfigured
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid provider URL"
        case .noAPIConfigured:
            "No API key configured"
        case .invalidResponse:
            "Invalid provider response"
        case let .apiError(message):
            message
        }
    }
}

/// Shared chat-completion transport for the Anthropic, Gemini, and OpenAI-compatible providers.
public struct ProviderHTTPClient: Sendable {
    let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    struct Request {
        let provider: AIProvider
        let baseURL: String
        let model: String
        let apiKey: String
        let systemMessage: String
        let userMessage: String
        let maxTokens: Int
        let anthropicAPIVersion: String
        let timeoutSeconds: TimeInterval
    }

    func send(_ request: Request) async throws -> String {
        let url = try Self.buildURL(
            provider: request.provider,
            baseURL: request.baseURL,
            model: request.model,
            apiKey: request.apiKey
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = request.timeoutSeconds

        switch request.provider {
        case .anthropic:
            urlRequest.setValue(request.apiKey, forHTTPHeaderField: "x-api-key")
            urlRequest.setValue(request.anthropicAPIVersion, forHTTPHeaderField: "anthropic-version")
        case .google:
            break
        case .openai, .groq, .custom:
            urlRequest.setValue("Bearer \(request.apiKey)", forHTTPHeaderField: "Authorization")
        }

        try Self.encodeBody(into: &urlRequest, for: request)

        let (data, response) = try await session.data(for: urlRequest)
        try Self.validateResponse(response, data: data)
        return try Self.parseContent(from: data, provider: request.provider)
    }

    private static func buildURL(
        provider: AIProvider,
        baseURL: String,
        model: String,
        apiKey: String
    ) throws -> URL {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL

        let endpoint: String
        switch provider {
        case .openai, .groq, .custom:
            endpoint = "\(base)/chat/completions"
        case .anthropic:
            endpoint = "\(base)/messages"
        case .google:
            let rawModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawModel.isEmpty else {
                throw ProviderHTTPClientError.noAPIConfigured
            }
            let normalizedModel = rawModel.hasPrefix("models/") ? rawModel : "models/\(rawModel)"
            endpoint = "\(base)/\(normalizedModel):generateContent"
        }

        guard var components = URLComponents(string: endpoint) else {
            throw ProviderHTTPClientError.invalidURL
        }

        if provider == .google {
            components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        }

        guard let url = components.url else {
            throw ProviderHTTPClientError.invalidURL
        }

        return url
    }

    private static func encodeBody(into request: inout URLRequest, for payload: Request) throws {
        let encoder = JSONEncoder()

        switch payload.provider {
        case .anthropic:
            let body = AnthropicMessageRequest(
                model: payload.model,
                maxTokens: payload.maxTokens,
                system: payload.systemMessage,
                messages: [AIChatMessage(role: "user", content: payload.userMessage)]
            )
            request.httpBody = try encoder.encode(body)
        case .google:
            let body = GeminiGenerateContentRequest(
                systemInstruction: GeminiSystemInstruction(parts: [GeminiPart(text: payload.systemMessage)]),
                contents: [GeminiContent(role: "user", parts: [GeminiPart(text: payload.userMessage)])],
                generationConfig: GeminiGenerationConfig(maxOutputTokens: payload.maxTokens)
            )
            request.httpBody = try encoder.encode(body)
        case .openai, .groq, .custom:
            let body = OpenAIChatRequest(
                model: payload.model,
                messages: [
                    AIChatMessage(role: "system", content: payload.systemMessage),
                    AIChatMessage(role: "user", content: payload.userMessage)
                ],
                maxTokens: payload.maxTokens
            )
            request.httpBody = try encoder.encode(body)
        }
    }

    private static func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderHTTPClientError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let decoder = JSONDecoder()
            if let errorResponse = try? decoder.decode(OpenAIErrorResponse.self, from: data) {
                throw ProviderHTTPClientError.apiError(errorResponse.error.message)
            }
            if let errorResponse = try? decoder.decode(AnthropicErrorResponse.self, from: data) {
                throw ProviderHTTPClientError.apiError(errorResponse.error.message)
            }
            if let errorResponse = try? decoder.decode(GeminiErrorResponse.self, from: data) {
                throw ProviderHTTPClientError.apiError(errorResponse.error.message)
            }

            let rawResponse = String(data: data, encoding: .utf8) ?? ""
            throw ProviderHTTPClientError.apiError("HTTP \(httpResponse.statusCode): \(rawResponse)")
        }
    }

    private static func parseContent(from data: Data, provider: AIProvider) throws -> String {
        let decoder = JSONDecoder()

        switch provider {
        case .anthropic:
            let response = try decoder.decode(AnthropicMessageResponse.self, from: data)
            guard let text = response.content.first?.text else {
                throw ProviderHTTPClientError.invalidResponse
            }
            return text
        case .google:
            let response = try decoder.decode(GeminiGenerateContentResponse.self, from: data)
            guard let text = response.candidates?.first?.content?.parts.first?.text else {
                throw ProviderHTTPClientError.invalidResponse
            }
            return text
        case .openai, .groq, .custom:
            let response = try decoder.decode(OpenAIChatResponse.self, from: data)
            guard let content = response.choices.first?.message.content else {
                throw ProviderHTTPClientError.invalidResponse
            }
            return content
        }
    }
}

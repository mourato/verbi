import Foundation
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

/// Service for interacting with LLM providers.
public protocol LLMService: Sendable {
    func validateURL(_ urlString: String) -> URL?
    func fetchAvailableModels(baseURL: URL, apiKey: String, provider: AIProvider) async throws -> [LLMModel]
    func testConnection(baseURL: URL, apiKey: String, provider: AIProvider) async throws -> Bool
}

public struct DefaultLLMService: LLMService {
    private let session: URLSession
    private let requestTimeout: TimeInterval = 10

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func validateURL(_ urlString: String) -> URL? {
        guard let url = URL(string: urlString),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased())
        else { return nil }
        return url
    }

    public func fetchAvailableModels(baseURL: URL, apiKey: String, provider: AIProvider) async throws -> [LLMModel] {
        let request = try buildModelsRequest(baseURL: baseURL, apiKey: apiKey, provider: provider)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw URLError(.badServerResponse)
        }

        if provider == .google {
            let response = try JSONDecoder().decode(GeminiModelsResponse.self, from: data)
            return response.models.map { model in
                let normalizedID = model.name.hasPrefix("models/")
                    ? String(model.name.dropFirst("models/".count))
                    : model.name
                return LLMModel(
                    id: normalizedID,
                    object: "model",
                    created: nil,
                    ownedBy: "google"
                )
            }
            .sorted { $0.id < $1.id }
        }

        let modelsResponse = try JSONDecoder().decode(LLMModelsResponse.self, from: data)
        return modelsResponse.data.sorted { $0.id < $1.id }
    }

    public func testConnection(baseURL: URL, apiKey: String, provider: AIProvider) async throws -> Bool {
        let request = try buildModelsRequest(baseURL: baseURL, apiKey: apiKey, provider: provider)

        let (_, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            return (200 ... 299).contains(httpResponse.statusCode)
        }
        return false
    }

    private func buildModelsRequest(baseURL: URL, apiKey: String, provider: AIProvider) throws -> URLRequest {
        let modelsURL: URL
        switch provider {
        case .google:
            guard var components = URLComponents(
                url: baseURL.appendingPathComponent("models"),
                resolvingAgainstBaseURL: false
            ) else {
                throw URLError(.badURL)
            }
            components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
            guard let url = components.url else {
                throw URLError(.badURL)
            }
            modelsURL = url
        case .openai, .groq, .anthropic, .custom:
            modelsURL = baseURL.appendingPathComponent("models")
        }

        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout

        switch provider {
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .google:
            break
        case .openai, .groq, .custom:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        return request
    }
}

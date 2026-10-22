import Foundation

/// Centralized configuration for external API services
public struct APIConfiguration: Sendable {
    public let baseURL: URL
    public let apiKey: String?
    public let timeout: TimeInterval

    public init(baseURL: URL, apiKey: String? = nil, timeout: TimeInterval = 30) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.timeout = timeout
    }
}

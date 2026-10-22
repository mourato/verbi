import Foundation

/// Unified network errors across all external services
public enum NetworkError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, data: Data)
    case decodingError(Error)
    case timeout
    case noConnection
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL configuration"
        case .invalidResponse:
            return "Invalid response from server"
        case let .httpError(code, _):
            return "HTTP error: \(code)"
        case let .decodingError(error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .timeout:
            return "Request timed out"
        case .noConnection:
            return "No internet connection"
        case .unauthorized:
            return "Authentication required"
        case let .rateLimited(retry):
            if let retry {
                return "Rate limited. Retry after \(Int(retry)) seconds"
            }
            return "Rate limited"
        }
    }
}

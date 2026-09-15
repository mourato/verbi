import Foundation

/// Defines an API endpoint with its properties
public struct APIEndpoint {
    public enum Method: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }

    public let url: URL
    public let method: Method
    public let headers: [String: String]
    public let body: Data?
    public let timeout: TimeInterval?

    public init(
        url: URL,
        method: Method = .get,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval? = nil
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

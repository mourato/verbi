import Foundation
import MeetingAssistantCoreCommon

/// Centralized HTTP client with consistent error handling and logging
public actor HTTPClient {
    private let session: URLSession
    private let defaultTimeout: TimeInterval

    public init(
        session: URLSession = .shared,
        timeout: TimeInterval = 30
    ) {
        self.session = session
        defaultTimeout = timeout
    }

    public func request<T: Decodable>(
        _ endpoint: APIEndpoint,
        responseType _: T.Type
    ) async throws -> T {
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = endpoint.method.rawValue
        request.timeoutInterval = endpoint.timeout ?? defaultTimeout

        for (key, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let body = endpoint.body {
            request.httpBody = body
        }

        AppLogger.debug("HTTP Request", category: .networkService, extra: [
            "method": endpoint.method.rawValue,
            "url": endpoint.url.absoluteString
        ])

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw NetworkError.httpError(statusCode: httpResponse.statusCode, data: data)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingError(error)
        }
    }

    public func upload(
        _ endpoint: APIEndpoint,
        fileURL: URL
    ) async throws -> Data {
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = endpoint.method.rawValue
        request.timeoutInterval = endpoint.timeout ?? defaultTimeout

        for (key, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        AppLogger.debug("HTTP Upload Request", category: .networkService, extra: [
            "method": endpoint.method.rawValue,
            "url": endpoint.url.absoluteString
        ])

        let (data, response) = try await session.upload(for: request, fromFile: fileURL)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw NetworkError.httpError(statusCode: httpResponse.statusCode, data: data)
        }

        return data
    }
}

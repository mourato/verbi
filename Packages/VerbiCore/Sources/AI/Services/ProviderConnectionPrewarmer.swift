import Foundation

public enum ProviderConnectionPrewarmer {
    public static func prewarm(baseURLs: [String], session: URLSession = .shared) {
        let origins = Set(baseURLs.compactMap(origin(of:)))
        for origin in origins {
            var request = URLRequest(url: origin)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 5
            session.dataTask(with: request).resume()
        }
    }

    static func origin(of baseURL: String) -> URL? {
        guard let components = URLComponents(string: baseURL),
              components.scheme == "https",
              let host = components.host, !host.isEmpty
        else { return nil }
        var origin = URLComponents()
        origin.scheme = "https"
        origin.host = host
        origin.port = components.port
        origin.path = "/"
        return origin.url
    }
}

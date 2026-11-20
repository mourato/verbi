import Foundation

/// Opens connections to remote providers while the user is still speaking.
///
/// The first request to a host pays for DNS, TCP and TLS setup, which measured
/// up to ~1.7 s for a dictation. Provider clients share `URLSession.shared`, so a
/// connection opened here stays in its pool and the real request reuses it.
/// The probe is a bare `HEAD` to the host root: no credentials, no content.
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

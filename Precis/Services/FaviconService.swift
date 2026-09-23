import Foundation

/// Fetches and caches favicons for feed domains.
public enum FaviconService {
    private static nonisolated(unsafe) var cache: [String: Data] = [:]

    /// Fetch the favicon for a given URL (tries /favicon.ico on the domain).
    public static func favicon(for urlString: String) async -> Data? {
        guard let url = URL(string: urlString),
              let host = url.host else { return nil }

        // Check cache
        if let cached = cache[host] { return cached }

        // Try common favicon paths
        let faviconURLs = [
            "https://\(host)/favicon.ico",
            "https://\(host)/apple-touch-icon.png",
            "https://\(host)/apple-touch-icon-precomposed.png"
        ]

        for faviconURL in faviconURLs {
            guard let faviconURL = URL(string: faviconURL) else { continue }
            do {
                var request = URLRequest(url: faviconURL)
                request.timeoutInterval = 5
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse,
                   (200...299).contains(httpResponse.statusCode),
                   data.count > 100 { // Ignore tiny/empty responses
                    cache[host] = data
                    return data
                }
            } catch {
                continue
            }
        }

        return nil
    }

    /// Clear the favicon cache.
    public static func clearCache() {
        cache.removeAll()
    }
}

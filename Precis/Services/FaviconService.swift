import Foundation

/// Fetches and caches favicons for feed domains.
///
/// An actor rather than the previous `nonisolated(unsafe)` static dictionary:
/// with a large sidebar every row kicks off a fetch on appear, so the old
/// cache was written from multiple tasks at once. Lookups/writes are now
/// serialized; the network requests themselves still run concurrently.
public actor FaviconService {
    public static let shared = FaviconService()

    private var cache: [String: Data] = [:]

    public init() {}

    /// Fetch the favicon for a given URL (tries /favicon.ico on the domain).
    public static func favicon(for urlString: String) async -> Data? {
        await shared.favicon(for: urlString)
    }

    /// Fetch the favicon for a given URL (tries /favicon.ico on the domain).
    public func favicon(for urlString: String) async -> Data? {
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
    public func clearCache() {
        cache.removeAll()
    }

    public static func clearCache() async {
        await shared.clearCache()
    }
}

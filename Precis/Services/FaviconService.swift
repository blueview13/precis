import AppKit
import Foundation

/// Fetches, validates and caches favicons for feed domains.
///
/// An actor rather than the previous `nonisolated(unsafe)` static dictionary:
/// with a large sidebar every row kicks off a fetch on appear, so the old
/// cache was written from multiple tasks at once. Lookups/writes are now
/// serialized; the network requests themselves still run concurrently.
///
/// Retrieval ladder — first usable image wins:
///  1. Convention paths (`/favicon.ico`, apple-touch icons)
///  2. Deep discovery: fetch the site's homepage and honour what it
///     declares (`<link rel="icon">` tags, largest first, plus `og:image` /
///     `twitter:image` as a last resort) — covers sites whose icon lives on
///     a CDN path, and sites serving junk at the root.
/// Every hit is validated (decodable, and not an empty canvas — some sites
/// ship fully transparent .ico files), downscaled to sidebar size, and
/// persisted to disk so relaunches show icons without a network round-trip.
/// Hosts that yield nothing are remembered for the session, so a dead or
/// bot-blocking host isn't re-hammered every time its row appears.
public actor FaviconService {
    public static let shared = FaviconService()

    private var cache: [String: Data] = [:]
    private var failedHosts: Set<String> = []
    private let diskDirectory: URL

    public init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        diskDirectory = base
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Precis", isDirectory: true)
            .appendingPathComponent("Favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
    }

    /// Fetch the favicon for a given URL (see the retrieval ladder above).
    public static func favicon(for urlString: String) async -> Data? {
        await shared.favicon(for: urlString)
    }

    /// Fetch the favicon for a given URL (see the retrieval ladder above).
    public func favicon(for urlString: String) async -> Data? {
        guard let url = URL(string: urlString),
              let host = url.host else { return nil }

        if let cached = cache[host] { return cached }
        if failedHosts.contains(host) { return nil }
        if let disk = diskLoad(host) {
            cache[host] = disk
            return disk
        }

        if let origin = Self.origin(of: url) {
            for path in ["favicon.ico", "apple-touch-icon.png", "apple-touch-icon-precomposed.png"] {
                if let candidate = URL(string: "\(origin)/\(path)"),
                   let hit = await resolve(candidate, host: host) {
                    return hit
                }
            }
            // Fast paths all failed or served junk — ask the homepage what
            // it declares before giving up on the host.
            for candidate in await Self.declaredIcons(origin: origin) {
                if let hit = await resolve(candidate, host: host) {
                    return hit
                }
            }
        }

        failedHosts.insert(host)
        return nil
    }

    private func resolve(_ candidate: URL, host: String) async -> Data? {
        guard let data = await Self.fetch(candidate, accept: Self.imageAccept),
              let usable = Self.usableImage(from: data) else { return nil }
        cache[host] = usable
        diskSave(host, usable)
        return usable
    }

    // MARK: - Homepage discovery

    private static func origin(of url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        // Keep an explicit port — dropping it would aim every request at
        // port 80/443 (breaks feeds served on a non-standard port).
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }

    /// Icon declarations from the site's homepage: `<link rel="icon">` tags
    /// (largest declared size first) followed by social-preview images.
    private static func declaredIcons(origin: String) async -> [URL] {
        guard let originURL = URL(string: origin),
              let data = await fetch(originURL, accept: htmlAccept) else { return [] }
        // Icon links all live in <head>; scanning the first MB is plenty.
        let html = String(data: data.prefix(1_000_000), encoding: .utf8) ?? ""
        guard !html.isEmpty else { return [] }

        let sized = tags(named: "link", in: html).compactMap { tag -> (Int, URL)? in
            guard let rel = attribute("rel", in: tag)?.lowercased(),
                  rel.contains("icon"),
                  let href = attribute("href", in: tag),
                  !href.hasPrefix("data:"),
                  let resolved = URL(string: href, relativeTo: originURL) else { return nil }
            return (iconSize(attribute("sizes", in: tag)), resolved.absoluteURL)
        }
        var ordered = sized.sorted { $0.0 > $1.0 }.map(\.1)

        for tag in tags(named: "meta", in: html) {
            let property = attribute("property", in: tag)?.lowercased()
            let name = attribute("name", in: tag)?.lowercased()
            guard property == "og:image" || name == "twitter:image",
                  let content = attribute("content", in: tag),
                  !content.hasPrefix("data:"),
                  let resolved = URL(string: content, relativeTo: originURL) else { continue }
            ordered.append(resolved.absoluteURL)
        }
        return ordered
    }

    private static func tags(named name: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "<\(name)\\b[^>]*>", options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "\\b\(name)\\s*=\\s*[\"']([^\"']+)[\"']",
            options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(tag.startIndex..., in: tag)
        guard let match = regex.firstMatch(in: tag, range: range),
              let capture = Range(match.range(at: 1), in: tag) else { return nil }
        return String(tag[capture])
    }

    /// Largest dimension in a `sizes` attribute ("32x32", "16x16 32x32").
    private static func iconSize(_ sizes: String?) -> Int {
        guard let sizes else { return 0 }
        return sizes.split(whereSeparator: { $0 == " " || $0 == "x" || $0 == "X" })
            .compactMap { Int($0) }
            .max() ?? 0
    }

    // MARK: - Fetching

    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    private static let imageAccept = "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8"
    private static let htmlAccept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"

    private static func fetch(_ url: URL, accept: String) async -> Data? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        // Browser-shaped requests: several CDNs 403 anything that looks like
        // a plain URL-loading client, even for public favicon files.
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse,
               (200...299).contains(http.statusCode) {
                return data
            }
        } catch {}
        return nil
    }

    // MARK: - Validation

    /// Returns sidebar-ready image data, or nil when the payload isn't a
    /// real, visible image (HTML error pages, transparent .ico placeholders).
    static func usableImage(from data: Data) -> Data? {
        guard data.count > 64,
              let rep = NSBitmapImageRep(data: data) else { return nil }
        let width = rep.pixelsWide, height = rep.pixelsHigh
        guard width > 0, height > 0 else { return nil }

        // Sample a grid — an icon with (almost) no visible pixels is junk.
        let stepX = max(1, width / 64), stepY = max(1, height / 64)
        var sampled = 0, visible = 0
        var y = 0
        while y < height {
            var x = 0
            while x < width {
                if let color = rep.colorAt(x: x, y: y) {
                    sampled += 1
                    if color.alphaComponent > 0.1 { visible += 1 }
                }
                x += stepX
            }
            y += stepY
        }
        guard sampled > 0, Double(visible) / Double(sampled) >= 0.01 else { return nil }

        guard max(width, height) > maximumIconSide else { return data }

        // Oversized previews (og:image is often 1200px wide) get shrunk so a
        // sidebar full of rows doesn't keep megabyte bitmaps alive. Falls
        // back to the original if drawing fails.
        let scale = CGFloat(maximumIconSide) / CGFloat(max(width, height))
        let targetWidth = max(1, Int(CGFloat(width) * scale))
        let targetHeight = max(1, Int(CGFloat(height) * scale))
        guard let small = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: targetWidth,
            pixelsHigh: targetHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return data }
        small.size = NSSize(width: targetWidth, height: targetHeight)
        guard let context = NSGraphicsContext(bitmapImageRep: small) else { return data }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        rep.draw(in: NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        NSGraphicsContext.restoreGraphicsState()
        return small.representation(using: .png, properties: [:]) ?? data
    }

    private static let maximumIconSide = 128

    // MARK: - Disk persistence

    private func diskURL(for host: String) -> URL {
        // Hosts can't contain "/" but may carry ":" (ports) — sanitize both.
        let name = host
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return diskDirectory.appendingPathComponent(name)
    }

    private func diskLoad(_ host: String) -> Data? {
        guard let data = try? Data(contentsOf: diskURL(for: host)) else { return nil }
        return Self.usableImage(from: data)
    }

    private func diskSave(_ host: String, _ data: Data) {
        try? data.write(to: diskURL(for: host), options: .atomic)
    }

    // MARK: - Cache control

    /// Clear the favicon cache.
    public func clearCache() {
        cache.removeAll()
        failedHosts.removeAll()
        try? FileManager.default.removeItem(at: diskDirectory)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
    }

    public static func clearCache() async {
        await shared.clearCache()
    }
}

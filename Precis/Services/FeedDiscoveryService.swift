import Foundation

public enum FeedDiscoveryError: Error, LocalizedError {
    case invalidURL
    case unsupportedInput
    case noFeedFound

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The feed URL is invalid."
        case .unsupportedInput:
            return "The URL could not be recognized as a feed or supported website."
        case .noFeedFound:
            return "No valid feed URL was found for this website."
        }
    }
}

public protocol FeedDiscoveryServiceProtocol: Sendable {
    func discover(from rawInput: String) async throws -> FeedDiscoveryResult
    func normalizeURL(_ rawInput: String) throws -> URL
    func validateFeedURL(_ url: URL) -> Bool
}

public final class FeedDiscoveryService: FeedDiscoveryServiceProtocol {
    public init() {}

    public func discover(from rawInput: String) async throws -> FeedDiscoveryResult {
        // Check for shorthand patterns first (r/subreddit, @handle, etc.)
        if let shorthand = try? await detectShorthand(rawInput) {
            return shorthand
        }

        let normalizedURL = try normalizeURL(rawInput)

        if let direct = try validateAndClassifyDirectFeed(for: normalizedURL) {
            return direct
        }

        if let youtubeResult = try? await detectYouTubeFeed(from: normalizedURL) {
            return youtubeResult
        }

        if let subredditResult = try await detectSubredditFeed(from: normalizedURL) {
            return subredditResult
        }

        if let googleNewsResult = try await detectGoogleNewsFeed(from: normalizedURL) {
            return googleNewsResult
        }

        if let twitterResult = try await detectTwitterFeed(from: normalizedURL) {
            return twitterResult
        }

        if let facebookResult = try await detectFacebookFeed(from: normalizedURL) {
            return facebookResult
        }

        if let mastodonResult = try await detectMastodonFeed(from: normalizedURL) {
            return mastodonResult
        }

        if let blueskyResult = try await detectBlueskyFeed(from: normalizedURL) {
            return blueskyResult
        }

        if let tiktokResult = try await detectTikTokFeed(from: normalizedURL) {
            return tiktokResult
        }

        if let githubResult = try await detectGitHubFeed(from: normalizedURL) {
            return githubResult
        }

        if let websiteResult = try await detectWebsiteAlternateFeed(from: normalizedURL) {
            return websiteResult
        }

        throw FeedDiscoveryError.noFeedFound
    }

    public func normalizeURL(_ rawInput: String) throws -> URL {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FeedDiscoveryError.invalidURL }

        let maybeURL: URL
        if let url = URL(string: trimmed), url.scheme != nil, url.host != nil {
            maybeURL = url
        } else if let url = URL(string: "https://\(trimmed)"), url.host != nil {
            maybeURL = url
        } else {
            throw FeedDiscoveryError.invalidURL
        }

        var components = URLComponents(url: maybeURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.scheme = components.scheme ?? "https"
        components.host = components.host ?? maybeURL.host
        components.path = components.path.isEmpty ? "/" : components.path

        guard let fixedURL = components.url else {
            throw FeedDiscoveryError.invalidURL
        }

        return fixedURL
    }

    public func validateFeedURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme, ["http", "https"].contains(scheme), url.host != nil else {
            return false
        }

        let lowerPath = url.path.lowercased()
        let knownFeedSuffixes = [".rss", ".xml", ".atom", ".rdf", ".json"]

        return knownFeedSuffixes.contains { lowerPath.hasSuffix($0) }
            || lowerPath.contains("/feed")
            || lowerPath.contains("/feeds")
            || lowerPath.contains("rss")
            || lowerPath.contains("atom")
            || lowerPath.contains("jsonfeed")
    }

    // MARK: - Display Titles

    /// Resolves a URL that may just be a site's home page (hand-written OPML
    /// files often record `xmlUrl` as `https://example.com`) to the site's
    /// actual feed URL.
    ///
    /// Strategy, in order:
    /// 1. A URL that already looks like a feed passes straight through.
    /// 2. Each candidate (as-is, http→https, bare host→www) is fetched and
    ///    scanned for a typed `<link rel="alternate">` RSS/Atom declaration.
    /// 3. Failing that, well-known feed paths (`/feed/`, `/rss`, …) are probed
    ///    and accepted when the response is feed-shaped.
    ///
    /// Returns `url` unchanged when nothing is found, so the caller can still
    /// attempt a direct fetch (and log the failure as before).
    public static func resolveFeedURL(_ url: URL) async -> URL {
        let service = FeedDiscoveryService()
        guard !service.validateFeedURL(url) else { return url }

        for candidate in service.homePageCandidates(for: url) {
            // Typed <link rel="alternate"> declaration in the page head.
            if let html = try? await service.fetchHTML(from: candidate),
               let link = service.feedLink(in: html, baseURL: candidate) {
                return link
            }
            // Well-known paths (WordPress, Ghost, Hugo…).
            for path in ["/feed/", "/rss", "/atom.xml", "/feed.xml", "/rss.xml"] {
                guard let probe = URL(string: path, relativeTo: candidate)?.absoluteURL else { continue }
                if await service.looksLikeFeed(probe) {
                    return probe
                }
            }
        }
        return url
    }

    /// The URLs worth trying for a possibly-home-page URL: the URL itself,
    /// its https twin (plain http is blocked by App Transport Security), and
    /// its www twin (bare hosts sometimes redirect into an http www host).
    func homePageCandidates(for url: URL) -> [URL] {
        var candidates: [URL] = [url]

        if url.scheme?.lowercased() == "http",
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = "https"
            if let upgraded = components.url { candidates.append(upgraded) }
        }

        if let host = url.host, !host.lowercased().hasPrefix("www."), host.contains("."),
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = "https"
            components.host = "www." + host
            if let wwwURL = components.url { candidates.append(wwwURL) }
        }

        return candidates
    }

    /// A feed URL advertised by a `<link rel="alternate">` tag — prefers a
    /// typed RSS/Atom/JSON declaration, then any href that is feed-shaped.
    /// Deliberately stricter than `findAlternateFeedLink` (used by `discover`):
    /// it must never pick oEmbed/mobile/hreflang alternates, because its
    /// result is probed no further.
    func feedLink(in html: String, baseURL: URL) -> URL? {
        guard let tagRegex = try? NSRegularExpression(pattern: #"<link\b[^>]*>"#, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var feedShapedFallback: URL?

        for match in tagRegex.matches(in: html, range: range) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])

            guard let rel = linkAttribute("rel", in: tag),
                  rel.lowercased().contains("alternate") else { continue }
            guard let href = linkAttribute("href", in: tag),
                  let link = resolveRelativeURL(href, baseURL: baseURL) else { continue }

            let type = (linkAttribute("type", in: tag) ?? "").lowercased()
            let typedFeed = type.contains("rss") || type.contains("atom")
                || type.contains("jsonfeed") || type.contains("feed+json")
            if typedFeed { return link }

            if feedShapedFallback == nil, validateFeedURL(link) {
                feedShapedFallback = link
            }
        }
        return feedShapedFallback
    }

    /// Attribute value from a single tag: `name="…"` or `name='…'`.
    private func linkAttribute(_ name: String, in tag: String) -> String? {
        let pattern = #"(?:^|\s)\(name)\s*=\s*"([^"]*)"|(?:^|\s)\(name)\s*=\s*'([^']*)'"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        guard let match = regex.firstMatch(in: tag, range: range) else { return nil }
        for group in [1, 2] where match.numberOfRanges > group {
            if let r = Range(match.range(at: group), in: tag), !r.isEmpty {
                return String(tag[r])
            }
        }
        return nil
    }

    /// True when `url` answers 2xx with something that is not HTML and either
    /// a feed content type or a feed XML/JSON payload.
    private func looksLikeFeed(_ url: URL) async -> Bool {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/rss+xml, application/atom+xml, application/xml, text/xml, */*", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else { return false }

        let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("html") { return false }
        if contentType.contains("rss") || contentType.contains("atom") || contentType.contains("xml") {
            return true
        }
        // Generic or missing content type — sniff the payload instead.
        guard let head = String(data: data.prefix(2048), encoding: .utf8) else { return false }
        let lowered = head.lowercased()
        return lowered.contains("<rss") || lowered.contains("<feed")
            || lowered.contains("https://jsonfeed.org/version")
    }

    /// True when a stored title is really a URL or bare host, e.g.
    /// "feeds.bbci.co.uk" or "https://example.com/feed.xml".
    public static func looksLikeURL(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.contains("://") { return true }
        // Scheme-less "host" or "host/path" — but require a dotted host so
        // friendly names like "r/macapps" or "mancity" are never misread.
        guard let host = URL(string: "https://\(trimmed)")?.host, host.contains(".") else { return false }
        return trimmed == host || trimmed.hasPrefix(host + "/")
    }

    /// Keeps friendly names ("r/macapps", "YouTube • mancity") but replaces
    /// URL-ish placeholders with the channel title read from the parsed feed.
    public static func displayTitle(current: String, parsedTitle: String?) -> String {
        guard looksLikeURL(current),
              let parsed = parsedTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !parsed.isEmpty
        else { return current }
        return parsed
    }

    /// Shortens a feed title for display: keeps the part before the first
    /// separator ("Al Jazeera – Breaking News…" → "Al Jazeera") and caps it
    /// at 4 words. Stored titles stay untouched.
    public static func conciseTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        var head = trimmed
        for separator in [" – ", " — ", " | ", " - ", " · ", ": "] {
            if let range = trimmed.range(of: separator) {
                head = String(trimmed[..<range.lowerBound])
                break
            }
        }

        let words = head.split(separator: " ", omittingEmptySubsequences: true)
        return words.count > 4 ? words.prefix(4).joined(separator: " ") : head
    }

    private func validateAndClassifyDirectFeed(for url: URL) throws -> FeedDiscoveryResult? {
        guard validateFeedURL(url) else { return nil }

        let title = url.host ?? "Feed"
        return FeedDiscoveryResult(
            originalInput: url.absoluteString,
            normalizedURL: url,
            title: title,
            kind: .directFeed,
            isDirectFeed: true
        )
    }

    func detectYouTubeFeed(from url: URL) async throws -> FeedDiscoveryResult? {
        let host = url.host?.lowercased() ?? ""
        guard host.contains("youtube.com") || host == "youtu.be" else { return nil }

        let path = url.path
        var channelID: String?
        var handle: String?

        if path.contains("/channel/") {
            channelID = path.components(separatedBy: "/channel/").last
        } else if path.contains("/user/") {
            channelID = path.components(separatedBy: "/user/").last
        } else if path.contains("/@") {
            handle = path.components(separatedBy: "/@").last
        }

        // Try to resolve @handle to channel ID via page fetch
        if let handle, !handle.isEmpty {
            channelID = try? await resolveYouTubeHandle(handle)
        }

        // If we have a channel ID, use the direct Atom feed
        if let channelID, !channelID.isEmpty {
            let youtubeURL = URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelID)")
            guard let youtubeURL else { return nil }
            let title = handle ?? channelID
            return FeedDiscoveryResult(
                originalInput: url.absoluteString,
                normalizedURL: youtubeURL,
                title: "YouTube • \(title)",
                kind: .youtube,
                isDirectFeed: true
            )
        }

        return nil
    }

    // MARK: - Shorthand Detection (r/subreddit, @handle, etc.)

    func detectShorthand(_ input: String) async throws -> FeedDiscoveryResult? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // r/subreddit → Reddit RSS
        if trimmed.hasPrefix("r/") {
            let subreddit = String(trimmed.dropFirst(2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "/", with: "")
            guard !subreddit.isEmpty else { return nil }

            let rssURL = URL(string: "https://www.reddit.com/r/\(subreddit)/.rss")
            guard let rssURL else { return nil }

            return FeedDiscoveryResult(
                originalInput: input,
                normalizedURL: rssURL,
                title: "r/\(subreddit)",
                kind: .subreddit,
                isDirectFeed: true
            )
        }

        // @handle → try YouTube first, then Twitter/X
        if trimmed.hasPrefix("@") {
            let handle = String(trimmed.dropFirst(1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !handle.isEmpty else { return nil }

            let youtubeURL = URL(string: "https://www.youtube.com/@\(handle)")!
            if let result = try? await detectYouTubeFeed(from: youtubeURL) {
                return result
            }

            let rssHubURL = URL(string: "https://rsshub.app/twitter/user/\(handle)")
            if let rssHubURL {
                return FeedDiscoveryResult(
                    originalInput: input,
                    normalizedURL: rssHubURL,
                    title: "@\(handle)",
                    kind: .twitter,
                    isDirectFeed: true
                )
            }
        }

        return nil
    }

    /// Resolve a YouTube @handle to a channel ID by fetching the page.
    private func resolveYouTubeHandle(_ handle: String) async throws -> String? {
        let profileURL = URL(string: "https://www.youtube.com/@\(handle)")
        guard let profileURL else { return nil }

        var request = URLRequest(url: profileURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        // Bypass YouTube GDPR consent page
        request.setValue("CONSENT=YES+cb; Domain=.youtube.com; Path=/; Max-Age=31536000", forHTTPHeaderField: "Cookie")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else { return nil }

        // Try "externalId":"UC..." (most reliable — YouTube's own identifier)
        let externalPattern = #""externalId":"(UC[a-zA-Z0-9_-]{22})"#
        if let regex = try? NSRegularExpression(pattern: externalPattern),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range])
        }

        // Fallback: channel/UC... in URL
        let channelPattern = #"channel/(UC[a-zA-Z0-9_-]{22})"#
        if let regex = try? NSRegularExpression(pattern: channelPattern),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range])
        }

        return nil
    }

    func detectSubredditFeed(from url: URL) async throws -> FeedDiscoveryResult? {
        let host = url.host?.lowercased() ?? ""
        guard host.contains("reddit.com") else { return nil }

        let pathParts = url.path.split(separator: "/").map(String.init)
        guard pathParts.count >= 2, pathParts[0] == "r", !pathParts[1].isEmpty else { return nil }

        let subreddit = pathParts[1]
        // Use old.reddit.com — it's less restrictive with RSS access
        let rssURL = URL(string: "https://www.reddit.com/r/\(subreddit)/.rss")
        guard let rssURL else { return nil }

        return FeedDiscoveryResult(
            originalInput: url.absoluteString,
            normalizedURL: rssURL,
            title: "r/\(subreddit)",
            kind: .subreddit,
            isDirectFeed: true
        )
    }

    // MARK: - Google News

    func detectGoogleNewsFeed(from url: URL) async throws -> FeedDiscoveryResult? {
        let host = url.host?.lowercased() ?? ""
        guard host.contains("news.google.com") else { return nil }

        // Already an RSS URL
        if url.path.contains("/rss") {
            return FeedDiscoveryResult(
                originalInput: url.absoluteString,
                normalizedURL: url,
                title: "Google News",
                kind: .googleNews,
                isDirectFeed: true
            )
        }

        // Extract search query from URL
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems,
           let query = queryItems.first(where: { $0.name == "q" })?.value {
            let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            let rssURL = URL(string: "https://news.google.com/rss/search?q=\(encodedQuery)&hl=en-US&gl=US&ceid=US:en")
            guard let rssURL else { return nil }
            return FeedDiscoveryResult(
                originalInput: url.absoluteString,
                normalizedURL: rssURL,
                title: "Google News • \(query)",
                kind: .googleNews,
                isDirectFeed: true
            )
        }

        // Generic Google News RSS
        let rssURL = URL(string: "https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en")
        guard let rssURL else { return nil }
        return FeedDiscoveryResult(
            originalInput: url.absoluteString,
            normalizedURL: rssURL,
            title: "Google News",
            kind: .googleNews,
            isDirectFeed: true
        )
    }

    // MARK: - X / Twitter (via RSSHub)

    func detectTwitterFeed(from url: URL) async throws -> FeedDiscoveryResult? {
        let host = url.host?.lowercased() ?? ""
        guard host.contains("x.com") || host.contains("twitter.com") else { return nil }

        let pathParts = url.path.split(separator: "/").map(String.init)
        guard let username = pathParts.first, !username.isEmpty, !username.hasPrefix("@") else { return nil }

        // Skip non-user paths
        let skipPaths = ["search", "explore", "notifications", "messages", "settings", "home", "i", "hashtag"]
        guard !skipPaths.contains(username.lowercased()) else { return nil }

        let rssURL = URL(string: "https://rsshub.app/twitter/user/\(username)")
        guard let rssURL else { return nil }

        return FeedDiscoveryResult(
            originalInput: url.absoluteString,
            normalizedURL: rssURL,
            title: "@\(username)",
            kind: .twitter,
            isDirectFeed: true
        )
    }

    // MARK: - Facebook (via RSSHub)

    func detectFacebookFeed(from url: URL) async throws -> FeedDiscoveryResult? {
        let host = url.host?.lowercased() ?? ""
        guard host.contains("facebook.com") || host.contains("fb.com") else { return nil }

        let pathParts = url.path.split(separator: "/").map(String.init)
        guard let pageName = pathParts.first, !pageName.isEmpty else { return nil }

        // Skip non-page paths
        let skipPaths = ["login", "signup", "groups", "events", "marketplace", "pages", "watch", "gaming"]
        guard !skipPaths.contains(pageName.lowercased()) else { return nil }

        let rssURL = URL(string: "https://rsshub.app/facebook/page/\(pageName)")
        guard let rssURL else { return nil }

        return FeedDiscoveryResult(
            originalInput: url.absoluteString,
            normalizedURL: rssURL,
            title: "Facebook • \(pageName)",
            kind: .facebook,
            isDirectFeed: true
        )
    }

    // MARK: - Mastodon (via RSSHub or native)

    func detectMastodonFeed(from url: URL) async throws -> FeedDiscoveryResult? {
        let host = url.host?.lowercased() ?? ""
        // Check for common Mastodon instances or custom domains
        guard host.contains("mastodon") || host.contains("fedibird") || host.contains("fosstodon") || host.contains("techhub.social") || host.contains("marsbar.social") || url.path.contains("/@") else { return nil }

        let pathParts = url.path.split(separator: "/").map(String.init)
        guard let username = pathParts.last, !username.isEmpty, username.hasPrefix("@") else { return nil }

        let cleanUsername = String(username.dropFirst()) // Remove @
        let rssURL = URL(string: "https://rsshub.app/mastodon/user/\(host)/\(cleanUsername)")
        guard let rssURL else { return nil }

        return FeedDiscoveryResult(
            originalInput: url.absoluteString,
            normalizedURL: rssURL,
            title: "@\(cleanUsername) @ \(host)",
            kind: .mastodon,
            isDirectFeed: true
        )
    }

    // MARK: - Bluesky (via RSSHub)

    func detectBlueskyFeed(from url: URL) async throws -> FeedDiscoveryResult? {
        let host = url.host?.lowercased() ?? ""
        guard host.contains("bsky.app") || host.contains("bluesky") else { return nil }

        let pathParts = url.path.split(separator: "/").map(String.init)
        guard let handle = pathParts.last, !handle.isEmpty else { return nil }

        let rssURL = URL(string: "https://rsshub.app/bluesky/user/\(handle)")
        guard let rssURL else { return nil }

        return FeedDiscoveryResult(
            originalInput: url.absoluteString,
            normalizedURL: rssURL,
            title: "@\(handle) (Bluesky)",
            kind: .bluesky,
            isDirectFeed: true
        )
    }

    // MARK: - TikTok (via RSSHub)

    func detectTikTokFeed(from url: URL) async throws -> FeedDiscoveryResult? {
        let host = url.host?.lowercased() ?? ""
        guard host.contains("tiktok.com") else { return nil }

        let pathParts = url.path.split(separator: "/").map(String.init)
        guard let username = pathParts.last, !username.isEmpty else { return nil }

        let rssURL = URL(string: "https://rsshub.app/tiktok/user/\(username)")
        guard let rssURL else { return nil }

        return FeedDiscoveryResult(
            originalInput: url.absoluteString,
            normalizedURL: rssURL,
            title: "@\(username) (TikTok)",
            kind: .tiktok,
            isDirectFeed: true
        )
    }

    // MARK: - GitHub (via releases/activity)

    func detectGitHubFeed(from url: URL) async throws -> FeedDiscoveryResult? {
        let host = url.host?.lowercased() ?? ""
        guard host.contains("github.com") else { return nil }

        let pathParts = url.path.split(separator: "/").map(String.init)
        // Expect /owner/repo
        guard pathParts.count >= 2 else { return nil }

        let owner = pathParts[0]
        let repo = pathParts[1]

        // Skip non-repo paths
        let skipPaths = ["settings", "notifications", "organizations", "enterprise", "features", "collections", "events", "sponsors"]
        guard !skipPaths.contains(owner.lowercased()), !skipPaths.contains(repo.lowercased()) else { return nil }

        let rssURL = URL(string: "https://github.com/\(owner)/\(repo)/releases.atom")
        guard let rssURL else { return nil }

        return FeedDiscoveryResult(
            originalInput: url.absoluteString,
            normalizedURL: rssURL,
            title: "\(owner)/\(repo)",
            kind: .github,
            isDirectFeed: true
        )
    }

    private func detectWebsiteAlternateFeed(from url: URL) async throws -> FeedDiscoveryResult? {
        let html = try await fetchHTML(from: url)
        guard let feedURL = findAlternateFeedLink(in: html, baseURL: url) else { return nil }

        return FeedDiscoveryResult(
            originalInput: url.absoluteString,
            normalizedURL: feedURL,
            title: url.host ?? "Website Feed",
            kind: .website,
            isDirectFeed: true
        )
    }

    private func fetchHTML(from url: URL) async throws -> String {
        let request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 15)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw FeedDiscoveryError.noFeedFound
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw FeedDiscoveryError.noFeedFound
        }

        return html
    }

    private func findAlternateFeedLink(in html: String, baseURL: URL) -> URL? {
        let pattern = "<link[^>]+rel=\"alternate\"[^>]+href=\"([^\"]+)\"|<link[^>]+href=\"([^\"]+)\"[^>]+rel=\"alternate\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: range)

        for match in matches {
            if let hrefRange = Range(match.range(at: 1), in: html) {
                let href = String(html[hrefRange])
                if let feedURL = resolveRelativeURL(href, baseURL: baseURL) {
                    return feedURL
                }
            }
            if let hrefRange = Range(match.range(at: 2), in: html) {
                let href = String(html[hrefRange])
                if let feedURL = resolveRelativeURL(href, baseURL: baseURL) {
                    return feedURL
                }
            }
        }

        return nil
    }

    private func resolveRelativeURL(_ href: String, baseURL: URL) -> URL? {
        let cleaned = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        if let absoluteURL = URL(string: cleaned), absoluteURL.scheme != nil, absoluteURL.host != nil {
            return absoluteURL
        }

        if let relativeURL = URL(string: cleaned, relativeTo: baseURL) {
            return relativeURL
        }

        return nil
    }
}

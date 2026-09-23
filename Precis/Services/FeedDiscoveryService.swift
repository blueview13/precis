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

import Foundation

public final class FeedDiscoveryServiceTests {
    public static func runSmokeChecks() {
        let service = FeedDiscoveryService()

        do {
            let directURL = try service.normalizeURL("https://example.com/rss.xml")
            assert(service.validateFeedURL(directURL))

            let youtubeURL = try service.normalizeURL("https://www.youtube.com/@apple")
            let youtubeResult = try awaitService { try await service.detectYouTubeFeed(from: youtubeURL) }
            assert(youtubeResult != nil)

            let subredditURL = try service.normalizeURL("https://www.reddit.com/r/swift/")
            let subredditResult = try awaitService { try await service.detectSubredditFeed(from: subredditURL) }
            assert(subredditResult != nil)
        } catch {
            print("Feed discovery smoke check failed: \(error)")
        }
    }

    private static func awaitService<T>(_ block: () async throws -> T?) -> T? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: T?
        var thrownError: Error?

        Task {
            do {
                result = try await block()
            } catch {
                thrownError = error
                result = nil
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let thrownError {
            print("Async test helper error: \(thrownError)")
            return nil
        }

        return result
    }
}

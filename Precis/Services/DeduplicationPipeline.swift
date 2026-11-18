import CryptoKit
import Foundation
import SwiftData

/// Small, deterministic checks used at ingest and display time. Hashing is
/// deliberately limited to the normalized headline; this is not fuzzy matching.
public enum DeduplicationPipeline {
    public static func canonicalURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        components.queryItems = components.queryItems?.filter { item in
            let key = item.name.lowercased()
            return !key.hasPrefix("utm_") && key != "ref" && key != "source"
        }
        if components.queryItems?.isEmpty == true { components.queryItems = nil }
        return components.string ?? url.absoluteString
    }

    public static func titleHash(_ title: String) -> String {
        let normalized = String(title.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        })
        return SHA256.hash(data: Data(normalized.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}

/// An immutable, Sendable article payload so normalization and hashing can
/// happen off the UI actor before SwiftData records are created.
public struct PreparedArticle: Sendable {
    public let entry: ParsedFeedEntry
    public let cleanURL: String?
    public let titleHash: String

    public init(entry: ParsedFeedEntry) {
        self.entry = entry
        self.cleanURL = entry.link.map(DeduplicationPipeline.canonicalURL)
        self.titleHash = DeduplicationPipeline.titleHash(entry.title)
    }
}

public actor ArticleIngestProcessor {
    public static let shared = ArticleIngestProcessor()

    private let storyClusters: StoryClusterService
    public init() { storyClusters = .shared }
    init(storyClusters: StoryClusterService) { self.storyClusters = storyClusters }

    public func prepare(_ entries: [ParsedFeedEntry]) -> [PreparedArticle] {
        entries.map(PreparedArticle.init(entry:))
    }

    /// Creates an isolated SwiftData context on this actor so duplicate
    /// lookups and inserts never run on the UI context's executor.
    @discardableResult
    public func ingest(_ entries: [PreparedArticle], feedID: UUID, container: ModelContainer) throws -> Int {
        guard !entries.isEmpty else { return 0 }
        let context = ModelContext(container)
        let targetFeedID = feedID
        let feedRequest = FetchDescriptor<FeedRecord>(predicate: #Predicate { $0.id == targetFeedID })
        guard let feed = try context.fetch(feedRequest).first else { return 0 }
        let repository = ArticleRepository()
        var inserted: [ArticleRecord] = []
        var insertedHashes: Set<String> = []
        var insertedURLs: Set<String> = []
        for prepared in entries {
            if insertedHashes.contains(prepared.titleHash)
                || prepared.cleanURL.map(insertedURLs.contains) == true { continue }
            guard try !repository.containsDuplicate(feedID: feedID, titleHash: prepared.titleHash,
                                                    cleanURL: prepared.cleanURL, context: context,
                                                    includePendingChanges: false) else { continue }
            let entry = prepared.entry
            let record = ArticleRecord(
                feed: feed,
                title: entry.title,
                cleanURL: prepared.cleanURL,
                titleHash: prepared.titleHash,
                author: entry.author,
                publishedDate: entry.publishedDate,
                link: entry.link?.absoluteString,
                rawContent: entry.content,
                extractedContent: entry.content,
                contentHTML: entry.contentHTML,
                imageURL: entry.imageURL?.absoluteString
            )
            context.insert(record)
            inserted.append(record)
            insertedHashes.insert(prepared.titleHash)
            if let url = prepared.cleanURL { insertedURLs.insert(url) }
        }
        guard !inserted.isEmpty else { return 0 }
        try context.save()
        // Article persistence completes immediately; the shared actor serializes background inference.
        let incoming = inserted.map { ArticleListItem(record: $0) }
        Task { await storyClusters.enqueue(incoming) }
        return inserted.count
    }

    @discardableResult
    public func ingestParsed(_ entries: [ParsedFeedEntry], feedID: UUID, container: ModelContainer) throws -> Int {
        try ingest(entries.map(PreparedArticle.init(entry:)), feedID: feedID, container: container)
    }
}

import Foundation
import SwiftData

public protocol FeedRepositoryProtocol {
    func fetchAll(context: ModelContext) throws -> [FeedRecord]
    func create(title: String, url: String, folder: FolderRecord?, context: ModelContext) throws -> FeedRecord
    func delete(_ feed: FeedRecord, context: ModelContext) throws
    func update(_ feed: FeedRecord, context: ModelContext) throws
}

public enum FeedRepositoryError: LocalizedError {
    case duplicateFeed(existingTitle: String)

    public var errorDescription: String? {
        switch self {
        case .duplicateFeed(let existingTitle):
            "This feed is already subscribed as \"\(existingTitle)\"."
        }
    }
}

public final class FeedRepository: FeedRepositoryProtocol {
    public init() {}

    public static func canonicalURLString(_ rawURL: String) -> String {
        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmedURL),
              let host = components.host else {
            return trimmedURL
        }

        components.scheme = components.scheme?.lowercased()
        components.host = host.lowercased()
        components.fragment = nil
        if (components.scheme == "http" && components.port == 80)
            || (components.scheme == "https" && components.port == 443) {
            components.port = nil
        }
        while components.path.count > 1 && components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        if components.path.isEmpty {
            components.path = "/"
        }

        return components.string ?? trimmedURL
    }

    public func existingFeed(forURL url: String, context: ModelContext) throws -> FeedRecord? {
        let canonicalURL = Self.canonicalURLString(url)
        return try context.fetch(FetchDescriptor<FeedRecord>())
            .first { Self.canonicalURLString($0.url) == canonicalURL }
    }

    public func fetchAll(context: ModelContext) throws -> [FeedRecord] {
        let descriptor = FetchDescriptor<FeedRecord>(sortBy: [SortDescriptor(\.title)])
        return try context.fetch(descriptor)
    }

    public func create(
        title: String,
        url: String,
        folder: FolderRecord?,
        context: ModelContext
    ) throws -> FeedRecord {
        if let existing = try existingFeed(forURL: url, context: context) {
            throw FeedRepositoryError.duplicateFeed(
                existingTitle: existing.sidebarTitle ?? existing.title
            )
        }

        let feed = FeedRecord(
            title: title,
            url: url,
            folder: folder,
            muted: false,
            lastFetched: nil
        )

        context.insert(feed)
        try context.save()
        return feed
    }

    public func delete(_ feed: FeedRecord, context: ModelContext) throws {
        context.delete(feed)
        try context.save()
    }

    public func update(_ feed: FeedRecord, context: ModelContext) throws {
        feed.lastFetched = Date()
        try context.save()
    }
}

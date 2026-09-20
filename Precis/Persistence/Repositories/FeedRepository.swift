import Foundation
import SwiftData

public protocol FeedRepositoryProtocol {
    func fetchAll(context: ModelContext) throws -> [FeedRecord]
    func create(title: String, url: String, folder: FolderRecord?, context: ModelContext) throws -> FeedRecord
    func delete(_ feed: FeedRecord, context: ModelContext) throws
    func update(_ feed: FeedRecord, context: ModelContext) throws
}

public final class FeedRepository: FeedRepositoryProtocol {
    public init() {}

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

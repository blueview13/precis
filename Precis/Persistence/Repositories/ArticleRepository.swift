import Foundation
import SwiftData

public protocol ArticleRepositoryProtocol {
    func fetchAll(context: ModelContext) throws -> [ArticleRecord]
    func fetch(id: UUID, context: ModelContext) throws -> ArticleRecord?
    func save(_ article: ArticleRecord, context: ModelContext) throws
    @discardableResult func saveIfNew(_ article: ArticleRecord, context: ModelContext) throws -> Bool
    func markRead(_ article: ArticleRecord, read: Bool, context: ModelContext) throws
    func toggleStarred(_ article: ArticleRecord, context: ModelContext) throws
}

public final class ArticleRepository: ArticleRepositoryProtocol {
    public init() {}

    public func fetchAll(context: ModelContext) throws -> [ArticleRecord] {
        let descriptor = FetchDescriptor<ArticleRecord>(sortBy: [SortDescriptor(\.publishedDate, order: .reverse)])
        return try context.fetch(descriptor)
    }

    /// Fetch one article by id. Per-click paths (toggle read/star, summary)
    /// used to fetchAll() the entire library and scan it — with 6k+ articles
    /// that materialized every record on every click.
    public func fetch(id: UUID, context: ModelContext) throws -> ArticleRecord? {
        let target = id
        let descriptor = FetchDescriptor<ArticleRecord>(
            predicate: #Predicate { $0.id == target }
        )
        return try context.fetch(descriptor).first
    }

    public func save(_ article: ArticleRecord, context: ModelContext) throws {
        context.insert(article)
        try context.save()
    }

    /// Save an article only if no article with the same title and feed already exists.
    /// Returns true if the article was saved, false if it was a duplicate.
    @discardableResult
    public func saveIfNew(_ article: ArticleRecord, context: ModelContext) throws -> Bool {
        let title = article.title
        let feedID = article.feed?.id
        let descriptor = FetchDescriptor<ArticleRecord>(
            predicate: #Predicate { record in
                record.title == title && record.feed?.id == feedID
            }
        )
        let existing = try context.fetch(descriptor)
        guard existing.isEmpty else { return false }
        context.insert(article)
        try context.save()
        return true
    }

    public func markRead(_ article: ArticleRecord, read: Bool, context: ModelContext) throws {
        article.isRead = read
        try context.save()
    }

    public func toggleStarred(_ article: ArticleRecord, context: ModelContext) throws {
        article.isStarred.toggle()
        try context.save()
    }
}

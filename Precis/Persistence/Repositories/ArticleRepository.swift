import Foundation
import SwiftData

public protocol ArticleRepositoryProtocol {
    func fetchAll(context: ModelContext) throws -> [ArticleRecord]
    func save(_ article: ArticleRecord, context: ModelContext) throws
    func markRead(_ article: ArticleRecord, read: Bool, context: ModelContext) throws
    func toggleStarred(_ article: ArticleRecord, context: ModelContext) throws
}

public final class ArticleRepository: ArticleRepositoryProtocol {
    public init() {}

    public func fetchAll(context: ModelContext) throws -> [ArticleRecord] {
        let descriptor = FetchDescriptor<ArticleRecord>(sortBy: [SortDescriptor(\.publishedDate, order: .reverse)])
        return try context.fetch(descriptor)
    }

    public func save(_ article: ArticleRecord, context: ModelContext) throws {
        context.insert(article)
        try context.save()
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

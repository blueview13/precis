import Foundation
import SwiftData

@Model
public final class FolderRecord {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var parentFolderID: UUID?
    public var smartFolderQuery: String?
    @Relationship(deleteRule: .cascade, inverse: \FeedRecord.folder) public var feeds: [FeedRecord] = []

    public init(
        id: UUID = UUID(),
        name: String,
        parentFolderID: UUID? = nil,
        smartFolderQuery: String? = nil
    ) {
        self.id = id
        self.name = name
        self.parentFolderID = parentFolderID
        self.smartFolderQuery = smartFolderQuery
    }
}

@Model
public final class FeedRecord {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var url: String
    public var folder: FolderRecord?
    public var muted: Bool
    public var lastFetched: Date?
    @Relationship(deleteRule: .cascade, inverse: \ArticleRecord.feed) public var articles: [ArticleRecord] = []

    public init(
        id: UUID = UUID(),
        title: String,
        url: String,
        folder: FolderRecord? = nil,
        muted: Bool = false,
        lastFetched: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.folder = folder
        self.muted = muted
        self.lastFetched = lastFetched
    }
}

@Model
public final class ArticleRecord {
    @Attribute(.unique) public var id: UUID
    public var feed: FeedRecord?
    public var title: String
    public var author: String?
    public var publishedDate: Date?
    public var link: String?
    @Attribute(.externalStorage) public var rawContent: Data?
    @Attribute(.externalStorage) public var extractedContent: Data?
    public var isRead: Bool
    public var isStarred: Bool
    public var imageURL: String?
    @Relationship(deleteRule: .cascade, inverse: \SummaryRecord.article) public var summary: SummaryRecord?

    public init(
        id: UUID = UUID(),
        feed: FeedRecord? = nil,
        title: String,
        author: String? = nil,
        publishedDate: Date? = nil,
        link: String? = nil,
        rawContent: String? = nil,
        extractedContent: String? = nil,
        isRead: Bool = false,
        isStarred: Bool = false,
        imageURL: String? = nil
    ) {
        self.id = id
        self.feed = feed
        self.title = title
        self.author = author
        self.publishedDate = publishedDate
        self.link = link
        self.rawContent = rawContent?.data(using: .utf8)
        self.extractedContent = extractedContent?.data(using: .utf8)
        self.isRead = isRead
        self.isStarred = isStarred
        self.imageURL = imageURL
    }

    public var rawContentText: String? {
        guard let rawContent else { return nil }
        return String(data: rawContent, encoding: .utf8)
    }

    public var extractedContentText: String? {
        guard let extractedContent else { return nil }
        return String(data: extractedContent, encoding: .utf8)
    }
}

@Model
public final class SummaryRecord {
    @Attribute(.unique) public var id: UUID
    public var article: ArticleRecord?
    public var shortText: String
    public var bulletPoints: [String]
    public var generatedBy: String
    public var generatedAt: Date

    public init(
        id: UUID = UUID(),
        article: ArticleRecord? = nil,
        shortText: String,
        bulletPoints: [String] = [],
        generatedBy: String,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.article = article
        self.shortText = shortText
        self.bulletPoints = bulletPoints
        self.generatedBy = generatedBy
        self.generatedAt = generatedAt
    }
}

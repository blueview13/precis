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
    public var sidebarTitle: String?
    public var url: String
    public var folder: FolderRecord?
    // Optional to-one relationship so existing stores migrate in-place (nullable column)
    public var category: CategoryRecord?
    public var muted: Bool
    public var lastFetched: Date?
    @Relationship(deleteRule: .cascade, inverse: \ArticleRecord.feed) public var articles: [ArticleRecord] = []

    public init(
        id: UUID = UUID(),
        title: String,
        sidebarTitle: String? = nil,
        url: String,
        folder: FolderRecord? = nil,
        category: CategoryRecord? = nil,
        muted: Bool = false,
        lastFetched: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.sidebarTitle = sidebarTitle
        self.url = url
        self.folder = folder
        self.category = category
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
    /// Raw HTML of the full article — either what the feed shipped
    /// (`content:encoded`) or the readable content fetched from the article
    /// link. Rendered richly (formatting + images) in the reading pane.
    @Attribute(.externalStorage) public var contentHTML: Data?
    /// True once the article's web page has been fetched and its readable
    /// content extracted, so a re-selection never re-downloads it.
    public var fullContentFetched: Bool?
    /// Plain-text rendering of the article body, computed once and persisted
    /// so app launch never re-runs the HTML-stripping pass over the whole
    /// library (regex over every article was ~0.5s of main-thread work per
    /// open with 6k+ articles). Nullable so existing stores migrate in-place.
    public var normalizedText: String?
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
        contentHTML: String? = nil,
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
        self.contentHTML = contentHTML?.data(using: .utf8)
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

    public var contentHTMLText: String? {
        guard let contentHTML else { return nil }
        return String(data: contentHTML, encoding: .utf8)
    }
}

@Model
public final class CategoryRecord {
    @Attribute(.unique) public var id: UUID
    public var name: String
    // Optional so stores created before this column existed migrate in-place
    // (a mandatory attribute would fail lightweight migration with 134110).
    public var sortOrder: Int?
    // Optional "#RRGGBB" tint for the sidebar's category text + icon.
    public var colorHex: String?
    // Deleting a category nullifies its feeds' category rather than deleting them
    @Relationship(deleteRule: .nullify, inverse: \FeedRecord.category)
    public var feeds: [FeedRecord] = []

    public init(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int? = nil,
        colorHex: String? = nil
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.colorHex = colorHex
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

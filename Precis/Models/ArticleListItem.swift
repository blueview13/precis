import Foundation

public struct ArticleListItem: Identifiable, Hashable {
    public let id: UUID
    public var title: String
    public var feedTitle: String
    public var publishedDate: Date?
    public var isRead: Bool
    public var isStarred: Bool
    public var snippet: String

    public init(
        id: UUID = UUID(),
        title: String,
        feedTitle: String,
        publishedDate: Date? = nil,
        isRead: Bool = false,
        isStarred: Bool = false,
        snippet: String = ""
    ) {
        self.id = id
        self.title = title
        self.feedTitle = feedTitle
        self.publishedDate = publishedDate
        self.isRead = isRead
        self.isStarred = isStarred
        self.snippet = snippet
    }
}

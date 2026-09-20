import Foundation

public struct Article: Identifiable, Codable, Hashable {
    public let id: UUID
    public var feedID: UUID
    public var title: String
    public var author: String?
    public var publishedDate: Date?
    public var link: URL?
    public var rawContent: String?
    public var extractedContent: String?
    public var isRead: Bool
    public var isStarred: Bool
    public var imageURL: URL?

    public init(
        id: UUID = UUID(),
        feedID: UUID,
        title: String,
        author: String? = nil,
        publishedDate: Date? = nil,
        link: URL? = nil,
        rawContent: String? = nil,
        extractedContent: String? = nil,
        isRead: Bool = false,
        isStarred: Bool = false,
        imageURL: URL? = nil
    ) {
        self.id = id
        self.feedID = feedID
        self.title = title
        self.author = author
        self.publishedDate = publishedDate
        self.link = link
        self.rawContent = rawContent
        self.extractedContent = extractedContent
        self.isRead = isRead
        self.isStarred = isStarred
        self.imageURL = imageURL
    }
}

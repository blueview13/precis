import Foundation

public struct Feed: Identifiable, Codable, Hashable {
    public let id: UUID
    public var title: String
    public var url: URL
    public var folderID: UUID?
    public var muted: Bool
    public var lastFetched: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        url: URL,
        folderID: UUID? = nil,
        muted: Bool = false,
        lastFetched: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.folderID = folderID
        self.muted = muted
        self.lastFetched = lastFetched
    }
}

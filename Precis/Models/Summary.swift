import Foundation

public struct Summary: Identifiable, Codable, Hashable {
    public let id: UUID
    public var articleID: UUID
    public var shortText: String
    public var bulletPoints: [String]
    public var generatedBy: String
    public var generatedAt: Date

    public init(
        id: UUID = UUID(),
        articleID: UUID,
        shortText: String,
        bulletPoints: [String] = [],
        generatedBy: String,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.articleID = articleID
        self.shortText = shortText
        self.bulletPoints = bulletPoints
        self.generatedBy = generatedBy
        self.generatedAt = generatedAt
    }
}

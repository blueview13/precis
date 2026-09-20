import Foundation

public struct Folder: Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var parentFolderID: UUID?
    public var smartFolderQuery: String?

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

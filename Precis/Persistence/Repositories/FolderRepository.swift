import Foundation
import SwiftData

public protocol FolderRepositoryProtocol {
    func fetchAll(context: ModelContext) throws -> [FolderRecord]
    func create(name: String, context: ModelContext) throws -> FolderRecord
    func delete(_ folder: FolderRecord, context: ModelContext) throws
    func rename(_ folder: FolderRecord, to name: String, context: ModelContext) throws
    func assignFeed(_ feed: FeedRecord, to folder: FolderRecord, context: ModelContext) throws
    func unassignFeed(_ feed: FeedRecord, context: ModelContext) throws
}

public final class FolderRepository: FolderRepositoryProtocol {
    public init() {}

    public func fetchAll(context: ModelContext) throws -> [FolderRecord] {
        let descriptor = FetchDescriptor<FolderRecord>(sortBy: [SortDescriptor(\.name)])
        return try context.fetch(descriptor)
    }

    public func create(name: String, context: ModelContext) throws -> FolderRecord {
        let folder = FolderRecord(name: name)
        context.insert(folder)
        try context.save()
        return folder
    }

    public func delete(_ folder: FolderRecord, context: ModelContext) throws {
        context.delete(folder)
        try context.save()
    }

    public func rename(_ folder: FolderRecord, to name: String, context: ModelContext) throws {
        folder.name = name
        try context.save()
    }

    public func assignFeed(_ feed: FeedRecord, to folder: FolderRecord, context: ModelContext) throws {
        feed.folder = folder
        try context.save()
    }

    public func unassignFeed(_ feed: FeedRecord, context: ModelContext) throws {
        feed.folder = nil
        try context.save()
    }
}

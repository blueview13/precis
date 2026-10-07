import Foundation
import SwiftData
import Testing

@testable import Precis

/// Offline tests for the one-time category → folder conversion and the
/// folder-delete guarantee that feeds survive their folder being deleted.
struct CategoryToFolderMigrationTests {

    private func makeContext() throws -> ModelContext {
        let schema = ModelContainerProvider.schema
        let configuration = ModelConfiguration(
            "CategoryToFolderMigrationTests",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(for: schema, configurations: configuration)
        return ModelContext(container)
    }

    @Test("Categories convert to folders with the same name, order, tint, and feeds")
    func convertsCategoriesToFolders() throws {
        let context = try makeContext()
        let category = CategoryRecord(name: "Tech", sortOrder: 3, colorHex: "#FF0000")
        context.insert(category)
        let feed = FeedRecord(title: "Hacker News", url: "https://news.ycombinator.com/rss")
        feed.category = category
        context.insert(feed)
        try context.save()

        #expect(try CategoryToFolderMigration.run(context: context) == 1)

        let folders = try context.fetch(FetchDescriptor<FolderRecord>())
        #expect(folders.count == 1)
        #expect(folders[0].name == "Tech")
        #expect(folders[0].sortOrder == 3)
        #expect(folders[0].colorHex == "#FF0000")
        #expect(feed.folder?.id == folders[0].id)
        // The legacy category stays populated so a rollback build still
        // reads the original organization.
        #expect(feed.category?.id == category.id)
    }

    @Test("A category sharing a name with an existing folder joins that folder")
    func mergesIntoSameNamedFolder() throws {
        let context = try makeContext()
        let existing = FolderRecord(name: "Tech")
        context.insert(existing)
        let category = CategoryRecord(name: "Tech", sortOrder: 1, colorHex: "#00FF00")
        context.insert(category)
        try context.save()

        #expect(try CategoryToFolderMigration.run(context: context) == 1)

        let folders = try context.fetch(FetchDescriptor<FolderRecord>())
        #expect(folders.count == 1)
        #expect(folders[0].id == existing.id)
        #expect(folders[0].sortOrder == 1)
        #expect(folders[0].colorHex == "#00FF00")
    }

    @Test("The category grouping wins when a feed is in both a folder and a category")
    func categoryWinsOverPreexistingFolder() throws {
        let context = try makeContext()
        let importedFolder = FolderRecord(name: "Imported")
        context.insert(importedFolder)
        let category = CategoryRecord(name: "News", sortOrder: 0)
        context.insert(category)
        let feed = FeedRecord(title: "Example", url: "https://example.com/rss", folder: importedFolder)
        feed.category = category
        context.insert(feed)
        try context.save()

        try CategoryToFolderMigration.run(context: context)

        let folders = try context.fetch(FetchDescriptor<FolderRecord>())
        #expect(folders.count == 2)
        #expect(feed.folder?.name == "News")
    }

    @Test("Deleting a folder never deletes the feeds inside it")
    func folderDeleteKeepsFeeds() throws {
        let context = try makeContext()
        let folder = FolderRecord(name: "Keep")
        context.insert(folder)
        let feed = FeedRecord(title: "Example", url: "https://example.com/rss", folder: folder)
        context.insert(feed)
        try context.save()

        try FolderRepository().delete(folder, context: context)

        #expect(try context.fetch(FetchDescriptor<FolderRecord>()).isEmpty)
        let remaining = try context.fetch(FetchDescriptor<FeedRecord>())
        #expect(remaining.count == 1)
        #expect(remaining[0].folder == nil)
    }
}

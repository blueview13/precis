import Foundation
import SwiftData

/// One-time conversion of the legacy sidebar categories (`CategoryRecord`)
/// into folders (`FolderRecord`), so a single grouping system backs both the
/// sidebar and the OPML export.
///
/// Categories are left in the store, still populated, so rolling back to a
/// pre-conversion build reads the original organization unchanged. Folders are
/// merged by name: a category whose name matches an existing (OPML-imported)
/// folder joins that folder instead of creating a twin.
public enum CategoryToFolderMigration {
    /// UserDefaults gate. Re-running after the user moved feeds between
    /// folders would re-apply the stale category assignment over that move.
    public static let completedFlagKey = "precis.categoryToFolderMigration.completed"

    /// Unguarded conversion — the entry point for tests. Returns the number
    /// of categories converted.
    @discardableResult
    public static func run(context: ModelContext) throws -> Int {
        let categories = try context.fetch(FetchDescriptor<CategoryRecord>())
        guard !categories.isEmpty else { return 0 }

        var foldersByName: [String: FolderRecord] = [:]
        for folder in try context.fetch(FetchDescriptor<FolderRecord>()) {
            foldersByName[folder.name] = folder
        }

        for category in categories {
            let folder: FolderRecord
            if let existing = foldersByName[category.name] {
                folder = existing
                if folder.sortOrder == nil { folder.sortOrder = category.sortOrder }
                if folder.colorHex == nil { folder.colorHex = category.colorHex }
            } else {
                folder = FolderRecord(
                    name: category.name,
                    colorHex: category.colorHex,
                    sortOrder: category.sortOrder
                )
                context.insert(folder)
                foldersByName[category.name] = folder
            }
            // The category wins over a pre-existing folder: the sidebar showed
            // this grouping before conversion, so it must keep showing it.
            for feed in category.feeds {
                feed.folder = folder
            }
        }
        try context.save()
        return categories.count
    }

    /// Run-once wrapper, called by the app when the store is opened.
    @discardableResult
    public static func runIfNeeded(context: ModelContext) throws -> Int {
        guard !UserDefaults.standard.bool(forKey: completedFlagKey) else { return 0 }
        let converted = try run(context: context)
        UserDefaults.standard.set(true, forKey: completedFlagKey)
        return converted
    }
}

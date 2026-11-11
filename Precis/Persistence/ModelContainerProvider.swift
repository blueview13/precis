import Foundation
import SwiftData

public enum ModelContainerProvider {
    public static let schema = Schema([
        FolderRecord.self,
        FeedRecord.self,
        ArticleRecord.self,
        SummaryRecord.self,
        CategoryRecord.self
    ])

    public static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(
            "PrecisStore",
            schema: schema,
            isStoredInMemoryOnly: false
        )

        let container = try ModelContainer(for: schema, configurations: config)
        // Convert legacy categories to folders before any view reads the store.
        let converted = try CategoryToFolderMigration.runIfNeeded(context: ModelContext(container))
        if converted > 0 {
            PrecisLogger.info("Converted \(converted) categor\(converted == 1 ? "y" : "ies") to folders")
        }
        try migrateArticleURLsIfNeeded(context: ModelContext(container))
        return container
    }

    /// Rebuild legacy keys which lowercased case-sensitive URL paths and queries.
    static func migrateArticleURLsIfNeeded(context: ModelContext, defaults: UserDefaults = .standard) throws {
        let key = "articleURLCaseNormalizationMigrated"
        guard !defaults.bool(forKey: key) else { return }
        let records = try context.fetch(FetchDescriptor<ArticleRecord>())
        var changed = false
        for record in records {
            guard let link = record.link, let url = URL(string: link) else { continue }
            let normalized = DeduplicationPipeline.canonicalURL(url)
            if record.cleanURL != normalized {
                record.cleanURL = normalized
                changed = true
            }
        }
        if changed { try context.save() }
        defaults.set(true, forKey: key)
    }
}

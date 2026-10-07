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
        return container
    }
}

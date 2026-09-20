import Foundation
import SwiftData

public enum ModelContainerProvider {
    public static let schema = Schema([
        FolderRecord.self,
        FeedRecord.self,
        ArticleRecord.self,
        SummaryRecord.self
    ])

    public static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(
            "PrecisStore",
            schema: schema,
            isStoredInMemoryOnly: false
        )

        return try ModelContainer(for: schema, configurations: config)
    }
}

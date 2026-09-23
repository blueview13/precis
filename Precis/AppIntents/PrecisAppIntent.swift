import AppIntents
import Foundation
import SwiftData

// MARK: - Model Container Helper for Intents

private enum IntentModelContainer {
    static func newContext() throws -> ModelContext {
        let container = try ModelContainerProvider.makeContainer()
        return ModelContext(container)
    }
}

// MARK: - Article Entity

@available(macOS 26.0, *)
struct ArticleEntity: AppEntity, Sendable {
    nonisolated(unsafe) static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Article"))
    nonisolated(unsafe) static let defaultQuery = ArticleEntityQuery()

    @Property(title: "Title")
    var title: String

    @Property(title: "Feed")
    var feedName: String

    @Property(title: "Summary")
    var summary: String

    var id: UUID

    var displayRepresentation: DisplayRepresentation {
        let label: LocalizedStringResource = "\(title) — \(feedName)"
        return DisplayRepresentation(title: label)
    }

    init(id: UUID, title: String, feedName: String, summary: String = "") {
        self.id = id
        self.title = title
        self.feedName = feedName
        self.summary = summary
    }
}

@available(macOS 26.0, *)
struct ArticleEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ArticleEntity] {
        let context = try IntentModelContainer.newContext()
        let allRecords = try context.fetch(FetchDescriptor<ArticleRecord>())
        let matched = allRecords.filter { identifiers.contains($0.id) }
        return matched.map { record in
            ArticleEntity(
                id: record.id,
                title: record.title,
                feedName: record.feed?.title ?? "Unknown"
            )
        }
    }

    func suggestedEntities() async throws -> [ArticleEntity] {
        let context = try IntentModelContainer.newContext()
        let allRecords = try context.fetch(FetchDescriptor<ArticleRecord>())
        let unread = allRecords
            .filter { !$0.isRead }
            .sorted { ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast) }
        return unread.prefix(10).map { record in
            ArticleEntity(
                id: record.id,
                title: record.title,
                feedName: record.feed?.title ?? "Unknown"
            )
        }
    }
}

// MARK: - Feed Entity

@available(macOS 26.0, *)
struct FeedEntity: AppEntity, Sendable {
    nonisolated(unsafe) static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Feed"))
    nonisolated(unsafe) static let defaultQuery = FeedEntityQuery()

    @Property(title: "Name")
    var name: String

    @Property(title: "URL")
    var url: String

    var id: UUID

    var displayRepresentation: DisplayRepresentation {
        let label: LocalizedStringResource = "\(name)"
        return DisplayRepresentation(title: label)
    }

    init(id: UUID, name: String, url: String) {
        self.id = id
        self.name = name
        self.url = url
    }
}

@available(macOS 26.0, *)
struct FeedEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [FeedEntity] {
        let context = try IntentModelContainer.newContext()
        let allRecords = try context.fetch(FetchDescriptor<FeedRecord>())
        let matched = allRecords.filter { identifiers.contains($0.id) }
        return matched.map { FeedEntity(id: $0.id, name: $0.title, url: $0.url) }
    }

    func suggestedEntities() async throws -> [FeedEntity] {
        let context = try IntentModelContainer.newContext()
        let records = try context.fetch(FetchDescriptor<FeedRecord>())
        return records.map { FeedEntity(id: $0.id, name: $0.title, url: $0.url) }
    }
}

// MARK: - Summarize Current Article Intent

@available(macOS 26.0, *)
struct SummarizeCurrentArticleIntent: AppIntent {
    static let title: LocalizedStringResource = "Summarize current article"
    static let description = IntentDescription("Generate a concise summary for a selected article in Precis.")
    static let openAppWhenRun = false

    @Parameter(title: "Article")
    var article: ArticleEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try IntentModelContainer.newContext()

        guard let articleID = article?.id else {
            return .result(dialog: IntentDialog(stringLiteral: "Please specify an article to summarize."))
        }

        let allRecords = try context.fetch(FetchDescriptor<ArticleRecord>())
        guard let record = allRecords.first(where: { $0.id == articleID }) else {
            return .result(dialog: IntentDialog(stringLiteral: "Could not find that article."))
        }

        let articleValue = Article(record: record)
        let summary = try await AppleIntelligenceSummarizationProvider().summarize(article: articleValue)

        let summaryRecord = SummaryRecord(
            article: record,
            shortText: summary.shortText,
            bulletPoints: summary.bulletPoints,
            generatedBy: summary.generatedBy,
            generatedAt: summary.generatedAt
        )
        record.summary = summaryRecord
        try SummaryRepository().save(summaryRecord, context: context)
        // Ensure the context is fully flushed so the app can see the summary
        try context.save()

        return .result(dialog: IntentDialog(stringLiteral: "Summary: \(summary.shortText)"))
    }
}

// MARK: - Summarize Unread Feed Intent

@available(macOS 26.0, *)
struct SummarizeUnreadFeedIntent: AppIntent {
    static let title: LocalizedStringResource = "Summarize unread items from a feed"
    static let description = IntentDescription("Summarize unread articles from a specific feed or all feeds.")
    static let openAppWhenRun = false

    @Parameter(title: "Feed")
    var target: FeedEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try IntentModelContainer.newContext()
        let allRecords = try context.fetch(FetchDescriptor<ArticleRecord>())

        let unreadRecords: [ArticleRecord]
        if let feedID = target?.id {
            unreadRecords = allRecords.filter { $0.feed?.id == feedID && !$0.isRead }
        } else {
            unreadRecords = allRecords.filter { !$0.isRead }
        }

        guard !unreadRecords.isEmpty else {
            return .result(dialog: IntentDialog(stringLiteral: "No unread articles to summarize."))
        }

        var summaries: [String] = []
        let provider = AppleIntelligenceSummarizationProvider()

        for record in unreadRecords.prefix(5) {
            let articleValue = Article(record: record)
            let summary = try await provider.summarize(article: articleValue)

            // Persist the summary so it's available in the app
            let summaryRecord = SummaryRecord(
                article: record,
                shortText: summary.shortText,
                bulletPoints: summary.bulletPoints,
                generatedBy: summary.generatedBy,
                generatedAt: summary.generatedAt
            )
            record.summary = summaryRecord
            try SummaryRepository().save(summaryRecord, context: context)

            summaries.append("\(record.title): \(summary.shortText)")
        }
        try context.save()

        let feedLabel = target?.name ?? "all feeds"
        let result = "Top \(summaries.count) from \(feedLabel):\n" + summaries.joined(separator: "\n")
        return .result(dialog: IntentDialog(stringLiteral: result))
    }
}

// MARK: - Add Feed Intent

@available(macOS 26.0, *)
struct AddFeedIntent: AppIntent {
    static let title: LocalizedStringResource = "Add feed"
    static let description = IntentDescription("Add a new RSS feed to Precis by URL.")
    static let openAppWhenRun = false

    @Parameter(title: "Feed URL")
    var url: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try IntentModelContainer.newContext()

        guard let feedURL = URL(string: url) else {
            return .result(dialog: IntentDialog(stringLiteral: "That doesn't look like a valid URL."))
        }

        let discoveryService = FeedDiscoveryService()
        let refreshService = FeedRefreshService()
        let feedRepository = FeedRepository()
        let articleRepository = ArticleRepository()

        let discoveryResult = try await discoveryService.discover(from: feedURL.absoluteString)
        let feed = try feedRepository.create(
            title: discoveryResult.title,
            url: discoveryResult.normalizedURL.absoluteString,
            folder: nil,
            context: context
        )

        let parsed = try await refreshService.fetchAndParse(
            Feed(title: discoveryResult.title, url: discoveryResult.normalizedURL)
        )

        for entry in parsed.entries {
            let record = ArticleRecord(
                feed: feed,
                title: entry.title,
                author: entry.author,
                publishedDate: entry.publishedDate,
                link: entry.link?.absoluteString,
                rawContent: entry.content,
                extractedContent: entry.content,
                isRead: false,
                isStarred: false,
                imageURL: entry.imageURL?.absoluteString
            )
            try articleRepository.saveIfNew(record, context: context)
        }

        return .result(dialog: IntentDialog(stringLiteral: "Added \"\(feed.title)\" with \(parsed.entries.count) articles."))
    }
}

// MARK: - Read Today's Headlines Intent

@available(macOS 26.0, *)
struct ReadHeadlinesIntent: AppIntent {
    static let title: LocalizedStringResource = "Read today's headlines"
    static let description = IntentDescription("Returns the titles of recent unread articles in Precis.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try IntentModelContainer.newContext()
        let descriptor = FetchDescriptor<ArticleRecord>(
            predicate: #Predicate { !$0.isRead },
            sortBy: [SortDescriptor(\.publishedDate, order: .reverse)]
        )
        let records = try context.fetch(descriptor)

        guard !records.isEmpty else {
            return .result(dialog: IntentDialog(stringLiteral: "No unread articles right now."))
        }

        let headlines = records.prefix(5).map { $0.title }
        let result = "Here are your top \(headlines.count) headlines:\n" + headlines.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return .result(dialog: IntentDialog(stringLiteral: result))
    }
}

// MARK: - Summarize Recent (Last 12 Hours) Intent

@available(macOS 26.0, *)
struct SummarizeRecentIntent: AppIntent {
    static let title: LocalizedStringResource = "Summarize recent articles"
    static let description = IntentDescription("Summarize all articles published in the last 12 hours across all feeds.")
    static let openAppWhenRun = false

    @Parameter(title: "Feed")
    var target: FeedEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try IntentModelContainer.newContext()
        let allRecords = try context.fetch(FetchDescriptor<ArticleRecord>())

        let twelveHoursAgo = Calendar.current.date(byAdding: .hour, value: -12, to: Date()) ?? Date()

        let recentRecords: [ArticleRecord]
        if let feedID = target?.id {
            recentRecords = allRecords.filter { record in
                guard let pubDate = record.publishedDate else { return false }
                return record.feed?.id == feedID && pubDate >= twelveHoursAgo
            }
        } else {
            recentRecords = allRecords.filter { record in
                guard let pubDate = record.publishedDate else { return false }
                return pubDate >= twelveHoursAgo
            }
        }

        guard !recentRecords.isEmpty else {
            let scope = target?.name ?? "any feed"
            return .result(dialog: IntentDialog(stringLiteral: "No articles from \(scope) in the last 12 hours."))
        }

        var summaries: [String] = []
        let provider = AppleIntelligenceSummarizationProvider()

        for record in recentRecords.prefix(10) {
            // Check if summary already exists
            if let existing = record.summary?.shortText, !existing.isEmpty {
                summaries.append("\(record.title): \(existing)")
                continue
            }

            let articleValue = Article(record: record)
            let summary = try await provider.summarize(article: articleValue)

            // Persist the summary
            let summaryRecord = SummaryRecord(
                article: record,
                shortText: summary.shortText,
                bulletPoints: summary.bulletPoints,
                generatedBy: summary.generatedBy,
                generatedAt: summary.generatedAt
            )
            record.summary = summaryRecord
            try SummaryRepository().save(summaryRecord, context: context)

            summaries.append("\(record.title): \(summary.shortText)")
        }
        try context.save()

        let scope = target?.name ?? "all feeds"
        let timeLabel = "last 12 hours"
        let result = "\(summaries.count) articles from \(scope) (\(timeLabel)):\n" + summaries.joined(separator: "\n\n")
        return .result(dialog: IntentDialog(stringLiteral: result))
    }
}

// MARK: - App Shortcuts Provider

@available(macOS 26.0, *)
struct PrecisAppShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SummarizeRecentIntent(),
            phrases: [
                "Summarize recent articles in \(.applicationName)",
                "What's new in \(.applicationName)",
                "Summarize the last 12 hours in \(.applicationName)",
                "Summarize recent from \(.applicationName)"
            ],
            shortTitle: "Summarize Recent",
            systemImageName: "text.book.closed"
        )

        AppShortcut(
            intent: ReadHeadlinesIntent(),
            phrases: [
                "Read my headlines in \(.applicationName)",
                "What are today's headlines in \(.applicationName)",
                "Read headlines from \(.applicationName)"
            ],
            shortTitle: "Read Headlines",
            systemImageName: "newspaper"
        )

        AppShortcut(
            intent: SummarizeUnreadFeedIntent(),
            phrases: [
                "Summarize unread in \(.applicationName)",
                "Summarize my feeds in \(.applicationName)",
                "Summarize articles in \(.applicationName)"
            ],
            shortTitle: "Summarize Unread",
            systemImageName: "text.magnifyingglass"
        )

        AppShortcut(
            intent: AddFeedIntent(),
            phrases: [
                "Add a feed to \(.applicationName)",
                "Subscribe to a feed in \(.applicationName)"
            ],
            shortTitle: "Add Feed",
            systemImageName: "plus.circle"
        )
    }
}

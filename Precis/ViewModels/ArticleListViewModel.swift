import Foundation
import SwiftData
import SwiftUI

@MainActor
public final class ArticleListViewModel: ObservableObject {
    @Published public var items: [ArticleListItem]
    @Published public var selectedItemID: UUID?
    @Published public var selectedFeedID: UUID?
    @Published public var searchText: String = ""
    @Published public var feedWideSummaryText: String = ""

    public var filteredItems: [ArticleListItem] {
        let base: [ArticleListItem]
        switch selectedSidebarFilter {
        case .all:
            base = items
        case .unread:
            base = items.filter { !$0.isRead }
        case .starred:
            base = items.filter { $0.isStarred }
        case .later:
            base = items.filter { !$0.isRead }
        case .feed(let feedID):
            base = items.filter { $0.feedID == feedID }
        case .folder(let folderID):
            let feedIDs = Set(allFeeds.filter { $0.folder?.id == folderID }.map(\.id))
            base = items.filter { item in
                guard let feedID = item.feedID else { return false }
                return feedIDs.contains(feedID)
            }
        }
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return base
        }
        let query = searchText.lowercased()
        return base.filter { $0.title.lowercased().contains(query) || $0.snippet.lowercased().contains(query) }
    }

    public enum SidebarFilter: Equatable {
        case all, unread, starred, later
        case feed(UUID)
        case folder(UUID)
    }

    @Published public var selectedSidebarFilter: SidebarFilter = .all

    /// All folders loaded from SwiftData.
    @Published public var folders: [FolderRecord] = []

    /// Feeds grouped by folder ID (nil key = unfiled feeds).
    public var feedsByFolder: [UUID?: [FeedRecord]] {
        Dictionary(grouping: allFeeds, by: \.folder?.id)
    }

    /// All feeds loaded from SwiftData.
    @Published public var allFeeds: [FeedRecord] = []

    public func loadFolders(context: ModelContext) {
        do {
            folders = try FolderRepository().fetchAll(context: context)
            allFeeds = try FeedRepository().fetchAll(context: context)
        } catch {
            folders = []
            allFeeds = []
        }
    }

    public func createFolder(name: String, context: ModelContext) {
        do {
            _ = try FolderRepository().create(name: name, context: context)
            loadFolders(context: context)
        } catch {}
    }

    public func deleteFolder(_ folder: FolderRecord, context: ModelContext) {
        do {
            // Unassign all feeds from this folder before deleting
            for feed in allFeeds where feed.folder?.id == folder.id {
                try FolderRepository().unassignFeed(feed, context: context)
            }
            try FolderRepository().delete(folder, context: context)
            loadFolders(context: context)
        } catch {}
    }

    public func unreadCountInFolder(_ folderID: UUID) -> Int {
        items.filter { item in
            guard let itemFeedID = item.feedID,
                  let feed = allFeeds.first(where: { $0.id == itemFeedID }),
                  feed.folder?.id == folderID else { return false }
            return !item.isRead
        }.count
    }

    public func unreadCount(forFeed feedID: UUID) -> Int {
        items.filter { $0.feedID == feedID && !$0.isRead }.count
    }

    public var totalUnreadCount: Int {
        items.filter { !$0.isRead }.count
    }

    private let articleRepository: ArticleRepositoryProtocol

    public init(
        items: [ArticleListItem] = [
            ArticleListItem(
                title: "The quiet power of good reading interfaces",
                feedTitle: "The Verge",
                publishedDate: Date().addingTimeInterval(-180),
                isRead: false,
                isStarred: true,
                snippet: "Quiet interfaces don’t subtract from the reading experience — they make it easier to trust the words in front of you."
            ),
            ArticleListItem(
                title: "How Apple Intelligence changes local summaries",
                feedTitle: "MacStories",
                publishedDate: Date().addingTimeInterval(-1260),
                isRead: false,
                isStarred: false,
                snippet: "Local inference is quietly becoming a major part of the reading experience on Apple devices."
            ),
            ArticleListItem(
                title: "Why RSS still feels essential on a focused machine",
                feedTitle: "Signals",
                publishedDate: Date().addingTimeInterval(-3600),
                isRead: true,
                isStarred: false,
                snippet: "The core appeal of RSS is not novelty; it is control, speed, and intentional reading."
            )
        ],
        articleRepository: ArticleRepositoryProtocol = ArticleRepository()
    ) {
        self.items = items
        self.selectedItemID = items.first?.id
        self.selectedFeedID = nil
        self.articleRepository = articleRepository
    }

    public var selectedItem: ArticleListItem? {
        guard let selectedItemID else { return items.first }
        return items.first(where: { $0.id == selectedItemID }) ?? items.first
    }

    public func loadFromContext(_ context: ModelContext) {
        do {
            let records = try articleRepository.fetchAll(context: context)
            if records.isEmpty {
                let seeded = try seedSampleRecords(in: context)
                items = seeded.map(ArticleListItem.init(record:))
                selectedFeedID = seeded.first?.feed?.id
            } else {
                items = records.map(ArticleListItem.init(record:))
                selectedFeedID = items.first?.id != nil ? nil : nil
            }
            selectedItemID = items.first?.id
        } catch {
            selectedItemID = items.first?.id
        }
    }

    public func loadArticles(for feedID: UUID?, context: ModelContext) {
        do {
            let records = try articleRepository.fetchAll(context: context)
            let filtered = feedID == nil ? records : records.filter { $0.feed?.id == feedID }
            items = filtered.map(ArticleListItem.init(record:))
            selectedFeedID = feedID
            selectedItemID = items.first?.id
        } catch {
            selectedFeedID = feedID
            selectedItemID = items.first?.id
        }
    }

    public func importFeed(from rawInput: String, in context: ModelContext) async throws {
        let discoveryService = FeedDiscoveryService()
        let refreshService = FeedRefreshService()
        let feedRepository = FeedRepository()

        let discoveryResult = try await discoveryService.discover(from: rawInput)
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

        let records = try articleRepository.fetchAll(context: context)
        items = records.map(ArticleListItem.init(record:))
        selectedItemID = items.first?.id
    }

    public func generateSummary(for item: ArticleListItem, in context: ModelContext) async throws -> SummaryRecord? {
        guard let articleRecord = try articleRepository.fetchAll(context: context).first(where: { $0.id == item.id }) else {
            return nil
        }

        let articleValue = Article(
            id: articleRecord.id,
            feedID: articleRecord.feed?.id ?? UUID(),
            title: articleRecord.title,
            author: articleRecord.author,
            publishedDate: articleRecord.publishedDate,
            link: articleRecord.link.flatMap { URL(string: $0) },
            rawContent: articleRecord.rawContentText,
            extractedContent: articleRecord.extractedContentText ?? articleRecord.rawContentText,
            isRead: articleRecord.isRead,
            isStarred: articleRecord.isStarred,
            imageURL: articleRecord.imageURL.flatMap { URL(string: $0) }
        )

        let summary = try await AppleIntelligenceSummarizationProvider().summarize(article: articleValue)

        // Don't save error messages or empty summaries
        guard !summary.shortText.isEmpty,
              !summary.shortText.lowercased().hasPrefix("summary unavailable"),
              !summary.shortText.lowercased().hasPrefix("no article content") else {
            return nil
        }

        let summaryRecord = SummaryRecord(
            article: articleRecord,
            shortText: summary.shortText,
            bulletPoints: summary.bulletPoints,
            generatedBy: summary.generatedBy,
            generatedAt: summary.generatedAt
        )

        articleRecord.summary = summaryRecord
        try SummaryRepository().save(summaryRecord, context: context)
        return summaryRecord
    }

    public func summaryText(for item: ArticleListItem, context: ModelContext) -> String? {
        do {
            return try SummaryRepository().fetch(for: item.id, context: context)?.shortText
        } catch {
            return nil
        }
    }

    /// Generate a bullet-point summary of articles from the last 12 hours.
    /// If feedID is provided, only summarizes articles from that feed.
    public func generateFeedWideSummary(context: ModelContext, feedID: UUID? = nil) async {
        do {
            let allRecords = try articleRepository.fetchAll(context: context)
            let twelveHoursAgo = Calendar.current.date(byAdding: .hour, value: -12, to: Date()) ?? Date()

            let recentRecords = allRecords.filter { record in
                guard let pubDate = record.publishedDate else { return false }
                let withinTimeframe = pubDate >= twelveHoursAgo
                if let feedID {
                    return withinTimeframe && record.feed?.id == feedID
                }
                return withinTimeframe
            }

            guard !recentRecords.isEmpty else {
                feedWideSummaryText = "No articles in the last 12 hours."
                return
            }

            // Collect titles and first sentences from each article
            var articleSummaries: [String] = []
            let provider = AppleIntelligenceSummarizationProvider()

            for record in recentRecords.prefix(15) {
                let articleValue = Article(record: record)
                let text = articleValue.extractedContent ?? articleValue.rawContent ?? articleValue.title
                let cleaned = text
                    .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if !cleaned.isEmpty {
                    articleSummaries.append("• \(record.title): \(cleaned.prefix(200))")
                }
            }

            guard !articleSummaries.isEmpty else {
                feedWideSummaryText = "No article content available to summarize."
                return
            }

            // Use FoundationModels to create a digest from the collected articles
            let combinedText = articleSummaries.joined(separator: "\n\n")
            let summary = try await provider.summarize(combinedText)

            let header = "**\(recentRecords.count) articles from the last 12 hours:**\n\n"
            feedWideSummaryText = header + summary.shortText

            // Also add bullet points if available
            if !summary.bulletPoints.isEmpty {
                feedWideSummaryText += "\n\n" + summary.bulletPoints.map { "• \($0)" }.joined(separator: "\n")
            }
        } catch {
            // Fallback: just list the article titles
            do {
                let allRecords = try articleRepository.fetchAll(context: context)
                let twelveHoursAgo = Calendar.current.date(byAdding: .hour, value: -12, to: Date()) ?? Date()
                let recentRecords = allRecords.filter { record in
                    guard let pubDate = record.publishedDate else { return false }
                    return pubDate >= twelveHoursAgo
                }
                if recentRecords.isEmpty {
                    feedWideSummaryText = "No articles in the last 12 hours."
                } else {
                    let titles = recentRecords.prefix(10).map { "• \($0.title)" }
                    feedWideSummaryText = "**\(recentRecords.count) recent articles:**\n\n" + titles.joined(separator: "\n")
                }
            } catch {
                feedWideSummaryText = "Could not load articles."
            }
        }
    }

    public func select(_ item: ArticleListItem) {
        selectedItemID = item.id
    }

    public func selectNext() {
        guard let currentID = selectedItemID,
              let index = filteredItems.firstIndex(where: { $0.id == currentID }),
              index + 1 < filteredItems.count else { return }
        selectedItemID = filteredItems[index + 1].id
    }

    public func selectPrevious() {
        guard let currentID = selectedItemID,
              let index = filteredItems.firstIndex(where: { $0.id == currentID }),
              index - 1 >= 0 else { return }
        selectedItemID = filteredItems[index - 1].id
    }

    public func toggleRead(_ item: ArticleListItem, context: ModelContext? = nil) {
        guard let context else {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].isRead.toggle()
            }
            return
        }

        do {
            let record = try articleRepository.fetchAll(context: context).first(where: { $0.id == item.id })
            guard let record else { return }

            try articleRepository.markRead(record, read: !record.isRead, context: context)

            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].isRead = !record.isRead
            }
        } catch {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].isRead.toggle()
            }
        }
    }

    public func markAllAsRead(context: ModelContext) {
        do {
            let records = try articleRepository.fetchAll(context: context)
            for record in records where !record.isRead {
                try articleRepository.markRead(record, read: true, context: context)
            }
            for index in items.indices {
                items[index].isRead = true
            }
        } catch {}
    }

    public func markAllAsUnread(context: ModelContext) {
        do {
            let records = try articleRepository.fetchAll(context: context)
            for record in records where record.isRead {
                try articleRepository.markRead(record, read: false, context: context)
            }
            for index in items.indices {
                items[index].isRead = false
            }
        } catch {}
    }

    public func toggleStarred(_ item: ArticleListItem, context: ModelContext? = nil) {
        guard let context else {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].isStarred.toggle()
            }
            return
        }

        do {
            let record = try articleRepository.fetchAll(context: context).first(where: { $0.id == item.id })
            guard let record else { return }

            try articleRepository.toggleStarred(record, context: context)

            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].isStarred = record.isStarred
            }
        } catch {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].isStarred.toggle()
            }
        }
    }

    private func seedSampleRecords(in context: ModelContext) throws -> [ArticleRecord] {
        let folder = FolderRecord(name: "News")
        let feedRepository = FeedRepository()
        let feed = try feedRepository.create(
            title: "The Verge",
            url: "https://www.theverge.com/rss/index.xml",
            folder: folder,
            context: context
        )

        let records = [
            ArticleRecord(
                feed: feed,
                title: "The quiet power of good reading interfaces",
                author: "The Verge",
                publishedDate: Date().addingTimeInterval(-180),
                rawContent: "Quiet interfaces don’t subtract from the reading experience — they make it easier to trust the words in front of you.",
                extractedContent: "Quiet interfaces don’t subtract from the reading experience — they make it easier to trust the words in front of you.",
                isRead: false,
                isStarred: true
            ),
            ArticleRecord(
                feed: feed,
                title: "How Apple Intelligence changes local summaries",
                author: "MacStories",
                publishedDate: Date().addingTimeInterval(-1260),
                rawContent: "Local inference is quietly becoming a major part of the reading experience on Apple devices.",
                extractedContent: "Local inference is quietly becoming a major part of the reading experience on Apple devices.",
                isRead: false,
                isStarred: false
            ),
            ArticleRecord(
                feed: feed,
                title: "Why RSS still feels essential on a focused machine",
                author: "Signals",
                publishedDate: Date().addingTimeInterval(-3600),
                rawContent: "The core appeal of RSS is not novelty; it is control, speed, and intentional reading.",
                extractedContent: "The core appeal of RSS is not novelty; it is control, speed, and intentional reading.",
                isRead: true,
                isStarred: false
            )
        ]

        for record in records {
            try articleRepository.save(record, context: context)
        }

        return records
    }
}

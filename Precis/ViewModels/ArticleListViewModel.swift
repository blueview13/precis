import Foundation
import SwiftData
import SwiftUI

@MainActor
public final class ArticleListViewModel: ObservableObject {
    @Published public var items: [ArticleListItem] {
        didSet { invalidateDerivedState() }
    }
    @Published public var selectedItemID: UUID?
    @Published public var selectedFeedID: UUID?
    @Published public var searchText: String = "" {
        didSet { invalidateDerivedState() }
    }
    @Published public var feedWideSummaryText: String = ""

    // MARK: Derived state (filtered rows + badge counts)

    // The sidebar badge pills and the list header used to run O(library)
    // scans on every render — `unreadCount(forFeed:)` filtered every article
    // once per sidebar row (400 rows × 6k articles), and `filteredItems` did
    // a full filter + sort 3-4× per render (isEmpty, count, ForEach) and
    // again on every arrow-key press. All cached here and dropped by
    // `invalidateDerivedState()` whenever an input changes.
    private var filteredItemsCache: [ArticleListItem]?
    private var unreadCountsByFeedCache: [UUID: Int]?
    private var unreadTotalCache: Int?
    private var starredTotalCache: Int?

    private func invalidateDerivedState() {
        filteredItemsCache = nil
        unreadCountsByFeedCache = nil
        unreadTotalCache = nil
        starredTotalCache = nil
    }

    private func rebuildCountCaches() {
        var byFeed: [UUID: Int] = [:]
        var unread = 0
        var starred = 0
        for item in items {
            if !item.isRead {
                unread += 1
                if let feedID = item.feedID {
                    byFeed[feedID, default: 0] += 1
                }
            }
            if item.isStarred {
                starred += 1
            }
        }
        unreadCountsByFeedCache = byFeed
        unreadTotalCache = unread
        starredTotalCache = starred
    }

    public var filteredItems: [ArticleListItem] {
        if let filteredItemsCache { return filteredItemsCache }
        let computed = computeFilteredItems()
        filteredItemsCache = computed
        return computed
    }

    private func computeFilteredItems() -> [ArticleListItem] {
        let base: [ArticleListItem]
        switch selectedSidebarFilter {
        case .all:
            base = items
        case .unread:
            base = items.filter { !$0.isRead }
        case .starred:
            base = items.filter { $0.isStarred }
        case .feed(let feedID):
            base = items.filter { $0.feedID == feedID }
        case .category(let categoryID):
            // Articles from every feed indented under this category, merged
            // into ONE list — `applySort` then orders them across feeds, so
            // rows are never grouped by their source feed. Resolve the feed
            // set ONCE: scanning `allFeeds` per item was O(articles × feeds).
            let categoryFeedIDs = Set(
                allFeeds.filter { $0.category?.id == categoryID }.map(\.id)
            )
            base = items.filter { item in
                guard let feedID = item.feedID else { return false }
                return categoryFeedIDs.contains(feedID)
            }
        case .folder(let folderID):
            let feedIDs = Set(allFeeds.filter { $0.folder?.id == folderID }.map(\.id))
            base = items.filter { item in
                guard let feedID = item.feedID else { return false }
                return feedIDs.contains(feedID)
            }
        }
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return applySort(to: base)
        }
        let query = searchText.lowercased()
        let matching = base.filter { $0.title.lowercased().contains(query) || $0.snippet.lowercased().contains(query) }
        return applySort(to: matching)
    }

    /// Settings → "Default sort order". Stored (not re-read on each access) so
    /// a change publishes through `objectWillChange` and every observer — the
    /// list, sidebar, header count — re-renders immediately. A UserDefaults
    /// observer registered in `init` keeps it in sync with the Settings window.
    @Published public var sortPreference: String = UserDefaults.standard.string(forKey: "defaultSortOrder") ?? "newest" {
        didSet { invalidateDerivedState() }
    }
    nonisolated(unsafe) private var sortObserver: NSObjectProtocol?

    /// Stable ordering — ties keep the underlying newest-first fetch order.
    private func applySort(to unsorted: [ArticleListItem]) -> [ArticleListItem] {
        let indexed = unsorted.enumerated().map { (index: $0.offset, item: $0.element) }
        let ordered: [(index: Int, item: ArticleListItem)]
        switch sortPreference {
        case "oldest":
            ordered = indexed.sorted {
                let l = $0.item.publishedDate ?? .distantPast
                let r = $1.item.publishedDate ?? .distantPast
                return l == r ? $0.index < $1.index : l < r
            }
        case "unread first":
            ordered = indexed.sorted {
                if $0.item.isRead != $1.item.isRead { return !$0.item.isRead }
                return $0.index < $1.index
            }
        case "starred first":
            ordered = indexed.sorted {
                if $0.item.isStarred != $1.item.isStarred { return $0.item.isStarred }
                return $0.index < $1.index
            }
        default: // "newest"
            ordered = indexed.sorted {
                let l = $0.item.publishedDate ?? .distantFuture
                let r = $1.item.publishedDate ?? .distantFuture
                return l == r ? $0.index < $1.index : l > r
            }
        }
        return ordered.map { $0.item }
    }

    public enum SidebarFilter: Equatable {
        case all, unread, starred
        case feed(UUID)
        case folder(UUID)
        case category(UUID)
    }

    @Published public var selectedSidebarFilter: SidebarFilter = .all {
        didSet {
            invalidateDerivedState()
            // The sidebar's current-feed highlight follows this filter —
            // leaving a feed for All/Unread/Starred/Category clears it.
            guard case .feed = selectedSidebarFilter else {
                selectedFeedID = nil
                return
            }
        }
    }

    /// All folders loaded from SwiftData.
    @Published public var folders: [FolderRecord] = []

    /// Feeds grouped by folder ID (nil key = unfiled feeds).
    public var feedsByFolder: [UUID?: [FeedRecord]] {
        Dictionary(grouping: allFeeds, by: \.folder?.id)
    }

    /// All feeds loaded from SwiftData. Category/folder filters resolve
    /// through this, so it feeds the derived-state cache as well.
    @Published public var allFeeds: [FeedRecord] = [] {
        didSet { invalidateDerivedState() }
    }

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
        if unreadCountsByFeedCache == nil { rebuildCountCaches() }
        guard let counts = unreadCountsByFeedCache else { return 0 }
        var total = 0
        for feed in allFeeds where feed.folder?.id == folderID {
            total += counts[feed.id] ?? 0
        }
        return total
    }

    public func unreadCount(forFeed feedID: UUID) -> Int {
        if unreadCountsByFeedCache == nil { rebuildCountCaches() }
        return unreadCountsByFeedCache?[feedID] ?? 0
    }

    public var totalUnreadCount: Int {
        if unreadTotalCache == nil { rebuildCountCaches() }
        return unreadTotalCache ?? 0
    }

    public var totalStarredCount: Int {
        if starredTotalCache == nil { rebuildCountCaches() }
        return starredTotalCache ?? 0
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

        // The Settings window writes "defaultSortOrder" from another window —
        // observe it and republish so the list re-sorts the moment it changes
        // (an unused @AppStorage alone was not invalidating the list).
        sortObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let updated = UserDefaults.standard.string(forKey: "defaultSortOrder") ?? "newest"
                if self.sortPreference != updated {
                    self.sortPreference = updated
                }
            }
        }
    }

    deinit {
        if let sortObserver {
            NotificationCenter.default.removeObserver(sortObserver)
        }
    }

    public var selectedItem: ArticleListItem? {
        guard let selectedItemID else { return items.first }
        return items.first(where: { $0.id == selectedItemID }) ?? items.first
    }

    public func loadFromContext(_ context: ModelContext) {
        do {
            let records = try articleRepository.fetchAll(context: context)
            if records.isEmpty {
                // An empty store stays empty — no demo seeding, so a freshly
                // wiped library opens as a genuine blank slate.
                items = []
                selectedFeedID = nil
                selectedItemID = nil
                return
            }
            rebuildItems(from: records, in: context)
            selectedFeedID = nil
            selectedItemID = items.first?.id
        } catch {
            selectedItemID = items.first?.id
        }
    }

    public func loadArticles(for feedID: UUID?, context: ModelContext) {
        do {
            let records = try articleRepository.fetchAll(context: context)
            // Always keep `items` as the FULL library: the sidebar pills count
            // unread/starred across every feed, and the `.feed` sidebar filter
            // narrows the visible rows. `rebuildItems` reuses already-parsed
            // entries, so reloading after every refresh is cheap even with
            // thousands of articles across hundreds of feeds.
            rebuildItems(from: records, in: context)
            selectedFeedID = feedID
            // Keep the selection inside the feed the user just opened.
            let scoped = feedID == nil ? items : items.filter { $0.feedID == feedID }
            selectedItemID = (scoped.first ?? items.first)?.id
        } catch {
            selectedFeedID = feedID
            selectedItemID = items.first?.id
        }
    }

    /// Rebuilds `items` from fetched records, REUSING already-parsed entries.
    ///
    /// The old code ran `ArticleListItem(record:)` for every article on every
    /// reload: that re-decoded raw + extracted content into Strings and
    /// re-ran the HTML-stripping regex over each body. During a refresh-all
    /// the reload fired after EVERY feed, so a 400-feed pass re-normalized the
    /// whole 6k-article library 400 times on the main thread — the sampled
    /// main thread spent most of its time in exactly this path.
    ///
    /// Article content is immutable once saved (`saveIfNew` never updates an
    /// existing row), so a seen record only needs its mutable flags refreshed.
    private func rebuildItems(from records: [ArticleRecord], in context: ModelContext) {
        var existing: [UUID: ArticleListItem] = [:]
        existing.reserveCapacity(items.count)
        for item in items {
            existing[item.id] = item
        }

        // Resolve feed titles from the already-loaded feed list instead of
        // faulting `record.feed` once per article.
        var feedTitles: [UUID: String] = [:]
        for feed in allFeeds {
            feedTitles[feed.id] = feed.title
        }

        var rebuilt: [ArticleListItem] = []
        rebuilt.reserveCapacity(records.count)
        var didBackfillNormalizedText = false

        for record in records {
            if var reused = existing[record.id] {
                reused.isRead = record.isRead
                reused.isStarred = record.isStarred
                if let feedID = reused.feedID,
                   let title = feedTitles[feedID],
                   reused.feedTitle != title {
                    reused.feedTitle = title
                }
                rebuilt.append(reused)
                continue
            }

            let item = ArticleListItem(record: record)
            // Persist the plain-text render on first sight so no later launch
            // has to re-run the HTML-stripping pass over this article.
            if record.normalizedText == nil {
                record.normalizedText = item.cleanSnippet
                didBackfillNormalizedText = true
            }
            rebuilt.append(item)
        }

        items = rebuilt
        if didBackfillNormalizedText {
            try? context.save()
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

        // Show the feed's own channel title (e.g. "BBC Sport") instead of a
        // URL/host placeholder (e.g. "feeds.bbci.co.uk")
        let displayTitle = FeedDiscoveryService.displayTitle(current: feed.title, parsedTitle: parsed.title)
        if displayTitle != feed.title {
            feed.title = displayTitle
            try context.save()
        }

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
        rebuildItems(from: records, in: context)
        selectedItemID = items.first?.id
    }

    public func generateSummary(for item: ArticleListItem, in context: ModelContext) async throws -> SummaryRecord? {
        guard let articleRecord = try articleRepository.fetch(id: item.id, context: context) else {
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

    /// In-flight summary run. Launch fires `generateFeedWideSummary` from
    /// several places at once; stacked runs each toggled isGeneratingSummary,
    /// forcing full-window layout passes that stalled the first right-click.
    /// Callers now share a single run instead.
    private var feedWideSummaryTask: Task<Void, Never>?

    /// Generate a bullet-point summary of articles from the last 12 hours.
    /// If feedID is provided, only summarizes articles from that feed.
    public func generateFeedWideSummary(context: ModelContext, feedID: UUID? = nil) async {
        if let running = feedWideSummaryTask {
            await running.value
            return
        }
        let task = Task { await self.performFeedWideSummary(context: context, feedID: feedID) }
        feedWideSummaryTask = task
        await task.value
        feedWideSummaryTask = nil
    }

    private func performFeedWideSummary(context: ModelContext, feedID: UUID?) async {
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

    public func select(_ item: ArticleListItem, context: ModelContext? = nil) {
        selectedItemID = item.id
        // Opening an article marks it read, so the unread pills drop right
        // away instead of staying until "d" or Mark All Read is pressed.
        guard let context, !item.isRead else { return }
        toggleRead(item, context: context)
    }

    public func selectNext() {
        guard !filteredItems.isEmpty else { return }
        if let currentID = selectedItemID,
           let index = filteredItems.firstIndex(where: { $0.id == currentID }) {
            guard index + 1 < filteredItems.count else { return }
            selectedItemID = filteredItems[index + 1].id
        } else {
            // The selection just left the list (it was marked read while the
            // Unread filter is active) — resume from the top row, don't stall.
            selectedItemID = filteredItems[0].id
        }
    }

    public func selectPrevious() {
        guard !filteredItems.isEmpty else { return }
        if let currentID = selectedItemID,
           let index = filteredItems.firstIndex(where: { $0.id == currentID }) {
            guard index - 1 >= 0 else { return }
            selectedItemID = filteredItems[index - 1].id
        } else {
            selectedItemID = filteredItems[filteredItems.count - 1].id
        }
    }

    public func toggleRead(_ item: ArticleListItem, context: ModelContext? = nil) {
        guard let context else {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].isRead.toggle()
            }
            return
        }

        do {
            let record = try articleRepository.fetch(id: item.id, context: context)
            guard let record else { return }

            try articleRepository.markRead(record, read: !record.isRead, context: context)

            // markRead already mutated `record.isRead` to the NEW value, so
            // mirror that value directly — the old `!record.isRead` computed
            // the OLD value here, which is why the first click never updated
            // the UI (the "double click to mark read" bug).
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].isRead = record.isRead
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
            let record = try articleRepository.fetch(id: item.id, context: context)
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

}

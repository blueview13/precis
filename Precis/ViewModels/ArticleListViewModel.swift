import Foundation
import SwiftData
import SwiftUI

@MainActor
public final class ArticleListViewModel: ObservableObject {
    @Published public var items: [ArticleListItem] {
        didSet { invalidateDerivedState() }
    }
    @Published public var selectedItemID: UUID? {
        // The Unread filter keeps the selected row visible, so the filtered
        // list now depends on the selection too.
        didSet { invalidateDerivedState() }
    }
    @Published public var selectedFeedID: UUID?
    @Published public var searchText: String = "" {
        didSet { invalidateDerivedState() }
    }
    @Published public var feedWideSummaryText: String = ""
    /// The article whose full web page is currently being downloaded and
    /// extracted — the reading pane shows a progress bar for it.
    @Published public var loadingFullContentID: UUID?
    /// Session-scoped guards so a dead link never re-hammers the network on
    /// every selection and an in-flight fetch is never started twice.
    private var fullContentInFlight: Set<UUID> = []
    private var fullContentFailed: Set<UUID> = []

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

    /// Message shown when the current filter has no rows. Shared by the
    /// list's empty state and the reading pane's empty state so both explain
    /// an empty filter with the same words.
    public var emptyStateTitle: String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No articles match your search"
        }
        switch selectedSidebarFilter {
        case .unread:
            return "You're all caught up — no unread articles"
        case .starred:
            return "No starred articles yet"
        case .category:
            return "No articles in this category yet"
        default:
            return "No articles here yet"
        }
    }

    private func computeFilteredItems() -> [ArticleListItem] {
        let base: [ArticleListItem]
        switch selectedSidebarFilter {
        case .all:
            base = items
        case .unread:
            // The open article stays visible while it's selected — marking it
            // read on click used to yank the row out from under the cursor and
            // let a random article shift into its place. It drops out on the
            // next selection change.
            base = items.filter { !$0.isRead || $0.id == selectedItemID }
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

    public enum SidebarFilter: Equatable, Hashable {
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
            // Keep the selection inside the feed the user just opened — but
            // never steal a still-valid one: refreshes run in the background,
            // and resetting to the top article made the list jump at random.
            let scoped = feedID == nil ? items : items.filter { $0.feedID == feedID }
            let selectionValid = selectedItemID.map { id in scoped.contains { $0.id == id } } ?? false
            if !selectionValid {
                selectedItemID = (scoped.first ?? items.first)?.id
            }
        } catch {
            selectedFeedID = feedID
            let stillValid = selectedItemID.map { id in items.contains { $0.id == id } } ?? false
            if !stillValid {
                selectedItemID = items.first?.id
            }
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
                contentHTML: entry.contentHTML,
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

    /// Fetches the article's full web page (once per article, persisted) and
    /// swaps the reading pane from the feed's short intro to the complete,
    /// formatted article — images and all. Falls back silently to whatever
    /// the feed supplied when there is no link or the fetch fails.
    public func loadFullContent(context: ModelContext) {
        guard let item = selectedItem,
              let link = item.link,
              let url = URL(string: link),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return }
        guard !fullContentInFlight.contains(item.id),
              !fullContentFailed.contains(item.id) else { return }

        let record: ArticleRecord?
        do {
            record = try articleRepository.fetch(id: item.id, context: context)
        } catch {
            return
        }
        guard let record else { return }

        if record.fullContentFetched == true {
            let stored = record.contentHTMLText ?? ""
            if !stored.isEmpty,
               ArticleContentLoader.visibleTextLength(in: stored) < ArticleContentLoader.minimumArticleText {
                // Saved before the quality gate existed (e.g. Reddit's JS
                // shell overwrote the feed's body) — drop the junk so the
                // pane falls back to the feed's own content, and don't trust
                // a re-fetch this session.
                record.contentHTML = nil
                record.fullContentFetched = false
                try? context.save()
                fullContentFailed.insert(item.id)
                applyRecord(record, to: item.id)
                return
            }
            // Already downloaded earlier — just make sure the visible item
            // carries the stored HTML (e.g. after an app relaunch).
            if item.contentHTML.isEmpty, !stored.isEmpty {
                applyRecord(record, to: item.id)
            }
            return
        }

        let id = item.id
        fullContentInFlight.insert(id)
        loadingFullContentID = id

        Task {
            defer {
                fullContentInFlight.remove(id)
                if loadingFullContentID == id {
                    loadingFullContentID = nil
                }
            }
            do {
                let html = try await ArticleContentLoader.fetchReadableHTML(from: url)
                guard let fetched = try articleRepository.fetch(id: id, context: context) else { return }
                fetched.contentHTML = html.data(using: .utf8)
                fetched.fullContentFetched = true
                // Promote the full plain text too, so row previews, search,
                // reading time and summaries see the whole article instead
                // of the feed's intro paragraph.
                let plain = HTMLAttributedStringRenderer.plainText(from: html)
                if !plain.isEmpty {
                    fetched.normalizedText = plain
                    fetched.extractedContent = plain.data(using: .utf8)
                }
                try context.save()
                applyRecord(fetched, to: id)
            } catch {
                // Offline, paywalled or a non-article page — keep the feed's
                // version and don't retry this article this session.
                fullContentFailed.insert(id)
            }
        }
    }

    /// Swaps one entry in `items` for a fresh parse of its record so the
    /// reading pane, reading time and row preview pick up new content.
    private func applyRecord(_ record: ArticleRecord, to id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index] = ArticleListItem(record: record)
    }

    /// Whether the visible list has an article above/below the current
    /// selection — greys out the matching ‹ › control in the reading pane.
    /// An off-list selection (marked read under the Unread filter) counts as
    /// navigable, matching `selectNext`/`selectPrevious`'s resume fallbacks.
    public var canSelectPrevious: Bool {
        guard !filteredItems.isEmpty else { return false }
        guard let currentID = selectedItemID,
              let index = filteredItems.firstIndex(where: { $0.id == currentID }) else { return true }
        return index > 0
    }

    public var canSelectNext: Bool {
        guard !filteredItems.isEmpty else { return false }
        guard let currentID = selectedItemID,
              let index = filteredItems.firstIndex(where: { $0.id == currentID }) else { return true }
        return index + 1 < filteredItems.count
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

    public func markAllAsRead(context: ModelContext, articleIDs: Set<UUID>? = nil) {
        do {
            let records = try articleRepository.fetchAll(context: context)
            let targetIDs = articleIDs ?? Set(records.map(\.id))
            for record in records where !record.isRead && targetIDs.contains(record.id) {
                try articleRepository.markRead(record, read: true, context: context)
            }
            for index in items.indices where targetIDs.contains(items[index].id) {
                items[index].isRead = true
            }
        } catch {}
    }

    public func markAllAsUnread(context: ModelContext, articleIDs: Set<UUID>? = nil) {
        do {
            let records = try articleRepository.fetchAll(context: context)
            let targetIDs = articleIDs ?? Set(records.map(\.id))
            for record in records where record.isRead && targetIDs.contains(record.id) {
                try articleRepository.markRead(record, read: false, context: context)
            }
            for index in items.indices where targetIDs.contains(items[index].id) {
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

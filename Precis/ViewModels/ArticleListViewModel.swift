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
    @Published public var feedWideSummaryProgress: Double = 0
    @Published public var isGeneratingFeedWideSummary = true
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
    /// Whether the cached `filteredItems` holds unread / read rows. The list
    /// header used to rescan the whole array twice per body evaluation.
    private var visibleHasUnreadCache = false
    private var visibleHasReadCache = false
    /// Cached lookup for the selected row — `selectedItem` was an O(library)
    /// linear scan, run several times per body evaluation.
    private var selectedItemCache: ArticleListItem?
    private var selectedItemCacheID: UUID?
    private var canSelectPreviousCache: Bool?
    private var canSelectNextCache: Bool?
    private var unreadCountsByFeedCache: [UUID: Int]?
    private var unreadTotalCache: Int?
    private var starredTotalCache: Int?

    private func invalidateDerivedState() {
        filteredItemsCache = nil
        visibleHasUnreadCache = false
        visibleHasReadCache = false
        selectedItemCacheID = nil
        canSelectPreviousCache = nil
        canSelectNextCache = nil
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
        visibleHasUnreadCache = computed.contains { !$0.isRead }
        visibleHasReadCache = computed.contains { $0.isRead }
        return computed
    }

    /// Whether the visible rows include unread / read articles — cached with
    /// `filteredItems` so the list header never rescans the array per render.
    public var visibleHasUnread: Bool {
        _ = filteredItems
        return visibleHasUnreadCache
    }

    public var visibleHasRead: Bool {
        _ = filteredItems
        return visibleHasReadCache
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

    @Published public var selectedSidebarFilter: SidebarFilter = .unread {
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
        if selectedItemCacheID == selectedItemID, let cached = selectedItemCache {
            return cached
        }
        let found = items.first(where: { $0.id == selectedItemID }) ?? items.first
        selectedItemCache = found
        selectedItemCacheID = selectedItemID
        return found
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
            // Select the TOP VISIBLE row, not just the top of the library —
            // with the Unread filter active at launch (the default), the
            // first unread article is what should open in the reading pane.
            selectedItemID = (filteredItems.first ?? items.first)?.id
        } catch {
            selectedItemID = (filteredItems.first ?? items.first)?.id
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
            // has to re-run the HTML-stripping pass over this article — and
            // rebuild renders written before the lead was cleaned of metadata
            // and entity codes (only when the rebuild actually changes them).
            let stored = record.normalizedText
            if stored == nil
                || (ArticleListItem.looksLikeMetadataLead(stored ?? "") && stored != item.cleanSnippet) {
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
    private var feedWideSummaryTaskFeedIDs: Set<UUID>?
    private var feedWideSummaryTaskGeneration: Int?
    private var feedWideSummaryGeneration = 0

    /// Generate a digest of up to 25 articles from the last 24 hours.
    /// If feedIDs is provided, only summarizes articles from those feeds.
    public func generateFeedWideSummary(context: ModelContext, feedIDs: Set<UUID>? = nil) async {
        if let running = feedWideSummaryTask {
            if feedWideSummaryTaskFeedIDs == feedIDs,
               feedWideSummaryTaskGeneration == feedWideSummaryGeneration {
                await running.value
                return
            }
        }

        feedWideSummaryGeneration += 1
        let generation = feedWideSummaryGeneration
        feedWideSummaryText = ""
        feedWideSummaryProgress = 0
        isGeneratingFeedWideSummary = true

        if let running = feedWideSummaryTask {
            await running.value
            guard generation == feedWideSummaryGeneration else { return }
        }

        feedWideSummaryTaskFeedIDs = feedIDs
        let task = Task {
            await self.performFeedWideSummary(context: context, feedIDs: feedIDs, generation: generation)
            guard self.feedWideSummaryGeneration == generation else { return }
            self.feedWideSummaryProgress = 1
            self.isGeneratingFeedWideSummary = false
            self.feedWideSummaryTask = nil
            self.feedWideSummaryTaskFeedIDs = nil
            self.feedWideSummaryTaskGeneration = nil
        }
        feedWideSummaryTask = task
        feedWideSummaryTaskGeneration = generation
        await task.value
    }

    private func updateFeedWideSummaryProgress(_ progress: Double, generation: Int) {
        guard generation == feedWideSummaryGeneration else { return }
        feedWideSummaryProgress = progress
    }

    private func updateFeedWideSummaryText(_ text: String, generation: Int) {
        guard generation == feedWideSummaryGeneration else { return }
        feedWideSummaryText = text
    }

    private func performFeedWideSummary(context: ModelContext, feedIDs: Set<UUID>?, generation: Int) async {
        do {
            updateFeedWideSummaryProgress(0.08, generation: generation)
            let allRecords = try articleRepository.fetchAll(context: context)
            let twentyFourHoursAgo = Calendar.current.date(byAdding: .hour, value: -24, to: Date()) ?? Date()

            let recentRecords = allRecords.filter { record in
                guard let pubDate = record.publishedDate else { return false }
                let withinTimeframe = pubDate >= twentyFourHoursAgo
                if let feedIDs {
                    return withinTimeframe && record.feed.map { feedIDs.contains($0.id) } == true
                }
                return withinTimeframe
            }
            updateFeedWideSummaryProgress(0.18, generation: generation)

            guard !recentRecords.isEmpty else {
                updateFeedWideSummaryText("No articles in the last 24 hours.", generation: generation)
                return
            }

            let digestRecords = Array(recentRecords.prefix(25))
            var articleSummaries: [String] = []
            let provider = AppleIntelligenceSummarizationProvider()

            for (index, record) in digestRecords.enumerated() {
                let articleValue = Article(record: record)
                let text = articleValue.extractedContent ?? articleValue.rawContent ?? articleValue.title
                // Strip tags AND decode entities — entity codes that reached
                // the digest prompt showed up verbatim in "Today's Precis".
                let cleaned = ArticleHTMLSanitizer.plainText(fromHTML: text)

                if !cleaned.isEmpty {
                    articleSummaries.append("• \(record.title): \(cleaned.prefix(200))")
                }
                updateFeedWideSummaryProgress(0.18 + 0.30 * Double(index + 1) / Double(digestRecords.count), generation: generation)
            }

            guard !articleSummaries.isEmpty else {
                updateFeedWideSummaryText("No article content available to summarize.", generation: generation)
                return
            }

            // Use FoundationModels to create a digest from the collected articles
            let combinedText = articleSummaries.joined(separator: "\n\n")
            updateFeedWideSummaryProgress(0.52, generation: generation)
            let summary = try await provider.summarizeDigest(combinedText) { progress in
                self.updateFeedWideSummaryProgress(0.52 + progress * 0.46, generation: generation)
            }

            let header = "**\(articleSummaries.count) articles from the last 24 hours:**\n\n"
            var summaryText = header + summary.shortText

            // Also add bullet points if available
            if !summary.bulletPoints.isEmpty {
                summaryText += "\n\n" + summary.bulletPoints.map { "• \($0)" }.joined(separator: "\n")
            }
            updateFeedWideSummaryText(summaryText, generation: generation)
        } catch {
            guard generation == feedWideSummaryGeneration else { return }
            // Fallback: just list the article titles
            do {
                let allRecords = try articleRepository.fetchAll(context: context)
                let twentyFourHoursAgo = Calendar.current.date(byAdding: .hour, value: -24, to: Date()) ?? Date()
                let recentRecords = allRecords.filter { record in
                    guard let pubDate = record.publishedDate else { return false }
                    guard pubDate >= twentyFourHoursAgo else { return false }
                    if let feedIDs {
                        return record.feed.map { feedIDs.contains($0.id) } == true
                    }
                    return true
                }
                if recentRecords.isEmpty {
                    updateFeedWideSummaryText("No articles in the last 24 hours.", generation: generation)
                } else {
                    let digestRecords = Array(recentRecords.prefix(25))
                    let titles = digestRecords.map { "• \($0.title)" }
                    updateFeedWideSummaryText("**\(digestRecords.count) articles from the last 24 hours:**\n\n" + titles.joined(separator: "\n"), generation: generation)
                }
            } catch {
                updateFeedWideSummaryText("Could not load articles.", generation: generation)
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
        if let canSelectPreviousCache { return canSelectPreviousCache }
        let value: Bool
        if filteredItems.isEmpty {
            value = false
        } else if let currentID = selectedItemID,
                  let index = filteredItems.firstIndex(where: { $0.id == currentID }) {
            value = index > 0
        } else {
            value = true
        }
        canSelectPreviousCache = value
        return value
    }

    public var canSelectNext: Bool {
        if let canSelectNextCache { return canSelectNextCache }
        let value: Bool
        if filteredItems.isEmpty {
            value = false
        } else if let currentID = selectedItemID,
                  let index = filteredItems.firstIndex(where: { $0.id == currentID }) {
            value = index + 1 < filteredItems.count
        } else {
            value = true
        }
        canSelectNextCache = value
        return value
    }

    /// Bumped by `selectNext`/`selectPrevious` (the pane's ‹ › buttons and
    /// the arrow keys) so the article list knows to animate-scroll to the
    /// newly selected row. Plain row clicks don't bump it — the list stays
    /// put when you click something already on screen.
    @Published public var listScrollRevealToken: Int = 0

    public func selectNext(context: ModelContext? = nil) {
        guard !filteredItems.isEmpty else { return }
        let outgoing = selectedItem
        if let currentID = selectedItemID,
           let index = filteredItems.firstIndex(where: { $0.id == currentID }) {
            guard index + 1 < filteredItems.count else { return }
            selectedItemID = filteredItems[index + 1].id
        } else {
            // The selection just left the list (it was marked read while the
            // Unread filter is active) — resume from the top row, don't stall.
            selectedItemID = filteredItems[0].id
        }
        markReadOnLeave(outgoing, context: context)
        listScrollRevealToken += 1
    }

    public func selectPrevious(context: ModelContext? = nil) {
        guard !filteredItems.isEmpty else { return }
        let outgoing = selectedItem
        if let currentID = selectedItemID,
           let index = filteredItems.firstIndex(where: { $0.id == currentID }) {
            guard index - 1 >= 0 else { return }
            selectedItemID = filteredItems[index - 1].id
        } else {
            selectedItemID = filteredItems[filteredItems.count - 1].id
        }
        markReadOnLeave(outgoing, context: context)
        listScrollRevealToken += 1
    }

    /// Navigating away means the open article has been read, so mark it —
    /// the article now showing keeps its unread dot until the reader moves
    /// off it (or presses `d`). No-op when there's nothing to move from or
    /// it's already read.
    private func markReadOnLeave(_ item: ArticleListItem?, context: ModelContext?) {
        guard let item, !item.isRead else { return }
        toggleRead(item, context: context)
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

    /// Single-article variant of `markAllAsRead` — fetches just that record
    /// (like the other per-click paths) so a headlines-panel click doesn't
    /// materialize the whole library.
    public func markRead(_ articleID: UUID, context: ModelContext) {
        do {
            if let record = try articleRepository.fetch(id: articleID, context: context), !record.isRead {
                try articleRepository.markRead(record, read: true, context: context)
            }
            if let index = items.firstIndex(where: { $0.id == articleID }) {
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

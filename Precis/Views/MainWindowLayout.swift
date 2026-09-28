import SwiftUI
import AppKit
import Combine
import SwiftData

struct MainWindowLayout: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: ArticleListViewModel
    @AppStorage("refreshIntervalMinutes") private var refreshIntervalMinutes: Int = 15
    @State private var backgroundRefresh = BackgroundRefreshService()
    @State private var selectedSidebarItem = "All Items"
    @State private var feedURLInput = ""
    @State private var isImporting = false
    @State private var isRefreshing = false
    @State private var isGeneratingSummary = false
    @State private var isRefreshingAll = false
    /// One or more feeds awaiting the delete confirmation — a single row's
    /// trash icon, a multi-selection, or every feed in a category.
    @State private var feedsPendingDeletion: [FeedRecord] = []
    /// Feeds checked for bulk actions via the row checkboxes (⌘/Shift still
    /// accelerate this, but nothing requires them — see the sidebar's
    /// "N selected" action bar).
    @State private var selectedFeedIDs: Set<UUID> = []
    /// Range anchor for Shift-click — the last feed clicked directly.
    @State private var selectionAnchorID: UUID?
    /// The sidebar takes key focus when a multi-selection exists so the
    /// Delete key lands on it (focus effect suppressed — no ring).
    @FocusState private var sidebarFocused: Bool
    @State private var importStatus = ""
    @State private var importStatusKind: ImportStatusKind = .neutral
    @State private var importedFeeds: [FeedRecord] = []
    @State private var showAddFeedSheet = false
    @State private var categories: [CategoryRecord] = []
    @State private var isAddingCategory = false
    @State private var newCategoryName = ""
    @State private var editingCategoryID: UUID?
    @State private var editingCategoryName = ""
    @FocusState private var isCategoryInputFocused: Bool
    @FocusState private var isCategoryEditFocused: Bool
    @State private var categoryDropTargetID: UUID?
    @State private var categoryRowHeights: [UUID: CGFloat] = [:]
    @State private var articleListHeight: CGFloat = 350
    @State private var windowHeight: CGFloat = 900
    @State private var sidebarWidth: CGFloat = 260
    @State private var isSidebarHidden = false
    @Environment(\.openWindow) private var openWindow
    private var selectedSummaryText: String? {
        guard let selectedItem = viewModel.selectedItem else { return nil }
        return viewModel.summaryText(for: selectedItem, context: modelContext)
    }

    init() {
        _viewModel = StateObject(wrappedValue: ArticleListViewModel())
    }

    var body: some View {
        HStack(spacing: 0) {
            // The sidebar slides out to the left (offset) while its layout
            // slot collapses, so the main pane expands smoothly instead of
            // the hide/show snapping instantly.
            sidebarView
                .frame(width: sidebarWidth)
                .overlay(alignment: .trailing) {
                    // Full-height sidebar border in the macOS accent color.
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 1)
                }
                .offset(x: isSidebarHidden ? -sidebarWidth : 0)
                .frame(width: isSidebarHidden ? 0 : sidebarWidth, alignment: .leading)
                .clipped()

            // Draggable vertical divider for sidebar resize — collapses with
            // the sidebar so no dead zone is left behind when it is hidden.
            Rectangle()
                .fill(Color.clear)
                .frame(width: isSidebarHidden ? 0 : 6)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            let newWidth = sidebarWidth + value.translation.width
                            sidebarWidth = max(180, min(newWidth, 400))
                        }
                )
                .onHover { inside in
                    if inside {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }

            VStack(spacing: 0) {
                ArticleListView(
                    viewModel: viewModel,
                    isSidebarHidden: isSidebarHidden,
                    onRevealSidebar: { isSidebarHidden = false }
                )
                .frame(height: articleListHeight)

                ResizableDivider()
                    .frame(height: 4)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let newHeight = articleListHeight + value.translation.height
                                // Clamp against the window itself (not a fixed
                                // fraction of the screen) so the divider can be
                                // dragged to any position down to the last 140pt.
                                let maxHeight = max(150, windowHeight - 140)
                                articleListHeight = max(150, min(newHeight, maxHeight))
                            }
                    )

                ReadingPaneView(
                    item: viewModel.selectedItem,
                    summaryOverride: selectedSummaryText,
                    feedWideSummary: viewModel.feedWideSummaryText,
                    isGeneratingSummary: isGeneratingSummary,
                    onGenerateSummary: {
                        Task {
                            isGeneratingSummary = true
                            await viewModel.generateFeedWideSummary(context: modelContext, feedID: viewModel.selectedFeedID)
                            isGeneratingSummary = false
                        }
                    },
                    onOpenInBrowser: {
                        guard let link = viewModel.selectedItem?.link,
                              let url = URL(string: link) else { return }
                        NSWorkspace.shared.open(url)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(PrecisDesignSystem.background(for: colorScheme))
        // Drives the sidebar slide-in/slide-out; every layout change keyed to
        // `isSidebarHidden` (sidebar slot, drag handle) animates together.
        .animation(.easeInOut(duration: 0.3), value: isSidebarHidden)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            // Used to clamp the horizontal divider to the real window height.
            windowHeight = height
            // If the window shrank below the current list height, pull it back
            // so the reading pane never gets pushed off-screen.
            let cap = max(150, height - 140)
            if articleListHeight > cap {
                articleListHeight = cap
            }
        }
        .onChange(of: viewModel.selectedFeedID) { _, _ in
            // Feed selection changed — regenerate digest for the new feed scope
            Task {
                isGeneratingSummary = true
                await viewModel.generateFeedWideSummary(context: modelContext, feedID: viewModel.selectedFeedID)
                isGeneratingSummary = false
            }
        }
        .onAppear {
            refreshFeeds()
            refreshCategories()
            viewModel.loadFromContext(modelContext)
            Task { await repairURLTitledFeeds() }
            viewModel.loadFolders(context: modelContext)
            startBackgroundRefresh()
            // Auto-generate feed-wide 12-hour summary on launch
            Task {
                isGeneratingSummary = true
                await viewModel.generateFeedWideSummary(context: modelContext, feedID: viewModel.selectedFeedID)
                isGeneratingSummary = false
            }
        }
        .onDisappear {
            backgroundRefresh.stopRefreshLoop()
        }
        .onChange(of: refreshIntervalMinutes) { _, _ in
            // Restart the loop with the interval picked in Settings
            startBackgroundRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .precisOpenSettings)) { _ in
            openWindow(id: "settings")
        }
        .onReceive(NotificationCenter.default.publisher(for: .precisFeedsImported)) { _ in
            // OPML import finished in the Settings window — reload the feed
            // list so the sidebar shows the new feeds immediately.
            refreshFeeds()
        }
    }

    // MARK: - Background refresh

    private var refreshInterval: RefreshInterval {
        RefreshInterval(rawValue: refreshIntervalMinutes) ?? .fifteenMinutes
    }

    private func startBackgroundRefresh() {
        backgroundRefresh.stopRefreshLoop()
        backgroundRefresh.beginRefreshLoop(interval: refreshInterval) {
            // Skip a tick that would collide with a manual "refresh all" pass.
            guard !isRefreshingAll else { return }
            PrecisLogger.info("Background refresh tick — refreshing all feeds")
            await refreshAllFeeds()
        }
    }

    private func refreshFeeds() {
        do {
            importedFeeds = try FeedRepository().fetchAll(context: modelContext)
            viewModel.loadFolders(context: modelContext)
            viewModel.loadArticles(for: viewModel.selectedFeedID, context: modelContext)
            // Regenerate feed-wide summary after refresh
            Task {
                await viewModel.generateFeedWideSummary(context: modelContext, feedID: viewModel.selectedFeedID)
            }
        } catch {
            importedFeeds = []
        }
    }

    // MARK: - Categories

    private func refreshCategories() {
        do {
            let fetched = try modelContext.fetch(FetchDescriptor<CategoryRecord>())
            // Legacy rows (sortOrder == nil) sort first by name, matching the
            // original alphabetical order; positioned rows keep their order.
            categories = fetched.sorted { lhs, rhs in
                switch (lhs.sortOrder, rhs.sortOrder) {
                case let (l?, r?) where l != r:
                    return l < r
                case (_?, nil):
                    return false
                case (nil, _?):
                    return true
                default:
                    return lhs.name < rhs.name
                }
            }
            normalizeCategoryOrder()
        } catch {
            PrecisLogger.error("Failed to load categories: \(error.localizedDescription)")
            categories = []
        }
    }

    /// Assigns contiguous positions so stored order survives relaunch,
    /// and repairs rows that predate `sortOrder`. Persists only when changed.
    private func normalizeCategoryOrder() {
        var changed = false
        for (index, category) in categories.enumerated() where category.sortOrder != index {
            category.sortOrder = index
            changed = true
        }
        guard changed else { return }
        do {
            try modelContext.save()
        } catch {
            PrecisLogger.error("Failed to normalize category order: \(error.localizedDescription)")
        }
    }

    private func createCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let nextOrder = (categories.compactMap(\.sortOrder).max() ?? -1) + 1
        modelContext.insert(CategoryRecord(name: name, sortOrder: nextOrder))
        do {
            try modelContext.save()
        } catch {
            PrecisLogger.error("Failed to create category: \(error.localizedDescription)")
        }

        newCategoryName = ""
        isAddingCategory = false
        isCategoryInputFocused = false
        refreshCategories()
    }

    private func beginEditingCategory(_ category: CategoryRecord) {
        editingCategoryID = category.id
        editingCategoryName = category.name
        DispatchQueue.main.async {
            isCategoryEditFocused = true
        }
    }

    private func commitCategoryRename() {
        guard let editingID = editingCategoryID,
              let category = categories.first(where: { $0.id == editingID }) else {
            cancelCategoryRename()
            return
        }

        let name = editingCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty && name != category.name {
            category.name = name
            do {
                try modelContext.save()
            } catch {
                PrecisLogger.error("Failed to rename category: \(error.localizedDescription)")
            }
        }

        editingCategoryID = nil
        isCategoryEditFocused = false
        refreshCategories()
    }

    private func cancelCategoryRename() {
        editingCategoryID = nil
        editingCategoryName = ""
        isCategoryEditFocused = false
    }

    private func deleteCategory(_ category: CategoryRecord) {
        modelContext.delete(category)
        do {
            try modelContext.save()
        } catch {
            PrecisLogger.error("Failed to delete category: \(error.localizedDescription)")
        }
        refreshCategories()
    }

    private func moveCategory(sourceID: UUID, targetID: UUID, insertAfter: Bool) {
        guard sourceID != targetID,
              let from = categories.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = categories.firstIndex(where: { $0.id == targetID })
        else { return }

        // If the computed placement is where the row already sits (dropping on
        // the neighbor it is directly next to), flip sides so a drop on a
        // different row always reorders. With only two categories the naive
        // placement would otherwise be a silent no-op.
        var after = insertAfter
        if after ? from == targetIndex + 1 : from == targetIndex - 1 {
            after.toggle()
        }

        withAnimation(.easeOut(duration: 0.2)) {
            let moved = categories.remove(at: from)
            var insertAt = categories.firstIndex(where: { $0.id == targetID }) ?? categories.count
            if after { insertAt += 1 }
            categories.insert(moved, at: insertAt)
        }
        normalizeCategoryOrder()
    }

    // MARK: - Feed ↔ Category

    private var uncategorizedFeeds: [FeedRecord] {
        importedFeeds.filter { $0.category == nil }
    }

    private func feeds(in category: CategoryRecord) -> [FeedRecord] {
        importedFeeds.filter { $0.category?.id == category.id }
    }

    private func moveFeed(_ feed: FeedRecord, to category: CategoryRecord?) {
        guard feed.category?.id != category?.id else { return }
        feed.category = category
        do {
            try modelContext.save()
        } catch {
            PrecisLogger.error("Failed to move feed to category: \(error.localizedDescription)")
        }
    }

    // MARK: - Feed multi-select & bulk delete

    /// Feed-row click (the checkbox toggles separately via
    /// `toggleFeedChecked`): a plain click just navigates to the feed and
    /// moves the Shift-range anchor, ⌘-click checks/unchecks, Shift-click
    /// checks the range between the anchor and this row *within its section*
    /// (a category's children and the ungrouped list are separate ranges —
    /// cross-section ranges would be ambiguous to read visually).
    private func handleFeedClick(_ feed: FeedRecord, group: [FeedRecord]) {
        let flags = NSEvent.modifierFlags
        let isCommand = flags.contains(.command)
        let isShift = flags.contains(.shift)

        if isShift,
           let anchorID = selectionAnchorID,
           let anchorIndex = group.firstIndex(where: { $0.id == anchorID }),
           let clickedIndex = group.firstIndex(where: { $0.id == feed.id }) {
            let lower = min(anchorIndex, clickedIndex)
            let upper = max(anchorIndex, clickedIndex)
            let rangeIDs = Set(group[lower...upper].map(\.id))
            if isCommand {
                selectedFeedIDs.formUnion(rangeIDs)
            } else {
                selectedFeedIDs = rangeIDs
            }
            if !selectedFeedIDs.isEmpty {
                // Arm the Delete-key shortcut, same as ticking a checkbox —
                // deferred so it can't disturb the click that set it.
                Task { @MainActor in
                    sidebarFocused = true
                }
            }
        } else if isCommand {
            toggleFeedChecked(feed)
            return
        }

        selectionAnchorID = feed.id
        viewModel.loadArticles(for: feed.id, context: modelContext)
        viewModel.selectedSidebarFilter = .feed(feed.id)
        selectedSidebarItem = feed.title
    }

    /// Checks/unchecks a feed's row checkbox. Checking arms the Delete-key
    /// shortcut — deferred to the next run-loop turn so the focus change
    /// can't interfere with the very tap that triggered it (a synchronous
    /// focus write inside the tap was suspect when checks didn't stick).
    private func toggleFeedChecked(_ feed: FeedRecord) {
        if selectedFeedIDs.contains(feed.id) {
            selectedFeedIDs.remove(feed.id)
        } else {
            selectedFeedIDs.insert(feed.id)
            selectionAnchorID = feed.id
        }
        // Diagnostic trail (Console.app): proves whether the tap reached
        // this point if checkbox behavior regresses again.
        PrecisLogger.info("Checkbox: \(feed.title) → checked=\(selectedFeedIDs.contains(feed.id)) total=\(selectedFeedIDs.count)")
        if !selectedFeedIDs.isEmpty {
            Task { @MainActor in
                sidebarFocused = true
            }
        }
    }

    /// Arms the shared delete confirmation for the current multi-selection.
    private func beginBulkDelete() {
        feedsPendingDeletion = importedFeeds.filter { selectedFeedIDs.contains($0.id) }
    }

    /// Runs after the confirmation alert: deletes every pending feed
    /// (articles cascade) in one pass and clears the selection.
    private func deletePendingFeeds() {
        let repository = FeedRepository()
        let count = feedsPendingDeletion.count
        do {
            for feed in feedsPendingDeletion {
                try repository.delete(feed, context: modelContext)
            }
            feedsPendingDeletion = []
            selectedFeedIDs.removeAll()
            selectionAnchorID = nil
            refreshFeeds()
            importStatus = count == 1 ? "Feed removed" : "\(count) feeds removed"
            importStatusKind = .success
        } catch {
            importStatus = "Could not remove feed"
            importStatusKind = .error
        }
    }

    /// "Remove from Category" — ungroup the feeds without deleting them.
    private func ungroupFeeds(_ feeds: [FeedRecord]) {
        for feed in feeds {
            feed.category = nil
        }
        do {
            try modelContext.save()
        } catch {
            PrecisLogger.error("Failed to ungroup feeds: \(error.localizedDescription)")
        }
        refreshFeeds()
    }

    private func sidebarFeedRow(_ feed: FeedRecord, indent: CGFloat = 0, compact: Bool = false, group: [FeedRecord] = []) -> some View {
        HStack {
            // Visible selection affordance — tick boxes make multi-select
            // discoverable without any keyboard combinations.
            //
            // Deliberately a tap gesture, not a Button: the category row
            // proves plain taps fire reliably in this sidebar, and the hit
            // area is padded past the 12pt circle so the size reduction
            // didn't leave a fussy target.
            Image(systemName: selectedFeedIDs.contains(feed.id) ? "checkmark.circle.fill" : "circle")
                // caption (10pt, down from body's 13pt) + 12pt box —
                // the checkbox shrunk ~25% to give titles more room.
                .font(.caption)
                .foregroundStyle(
                    selectedFeedIDs.contains(feed.id)
                        ? Color.accentColor
                        : PrecisDesignSystem.marginalia.opacity(0.35)
                )
                .frame(width: 12, height: 12)
                .contentShape(Rectangle().inset(by: -5))
                .onTapGesture { toggleFeedChecked(feed) }
                .help("Check to select for bulk actions")

            Button(action: {
                handleFeedClick(feed, group: group)
            }) {
                HStack(spacing: 8) {
                    FeedFaviconView(url: feed.url)
                        .frame(width: 16, height: 16)
                    Text(FeedDiscoveryService.conciseTitle(feed.title))
                        .font(PrecisTypography.body)
                        .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.8))
                }
            }
            .buttonStyle(.plain)

            let feedUnread = viewModel.unreadCount(forFeed: feed.id)
            if feedUnread > 0 {
                Text("\(feedUnread)")
                    .font(PrecisTypography.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }

            Spacer()

            if !compact, let lastFetched = feed.lastFetched {
                Text(relativeTimeString(from: lastFetched))
                    .font(PrecisTypography.caption)
                    .foregroundStyle(PrecisDesignSystem.marginalia.opacity(0.7))
            }
            // Refresh and delete no longer have per-row icons — refresh lives
            // in the context menu; delete is the checkbox action bar (and
            // also in the context menu).
        }
        .padding(.leading, indent)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    viewModel.selectedFeedID == feed.id || selectedFeedIDs.contains(feed.id)
                        ? Color.accentColor.opacity(0.12)
                        : Color.clear
                )
        )
        .contextMenu {
            Button {
                Task { await refreshSingleFeed(feed) }
            } label: {
                Label("Refresh Feed", systemImage: "arrow.clockwise")
            }
            Divider()
            if selectedFeedIDs.count >= 2 && selectedFeedIDs.contains(feed.id) {
                Button(role: .destructive) {
                    beginBulkDelete()
                } label: {
                    Label("Delete \(selectedFeedIDs.count) Feeds…", systemImage: "trash")
                }
            } else {
                Button(role: .destructive) {
                    // Deletion happens only after the confirmation alert.
                    feedsPendingDeletion = [feed]
                } label: {
                    Label("Delete Feed…", systemImage: "trash")
                }
            }
            Divider()
            Menu {
                Button {
                    moveFeed(feed, to: nil)
                } label: {
                    Label("No Category", systemImage: feed.category == nil ? "checkmark" : "square")
                }
                Divider()
                if categories.isEmpty {
                    Text("No categories yet")
                } else {
                    ForEach(categories) { category in
                        Button {
                            moveFeed(feed, to: category)
                        } label: {
                            Label(category.name, systemImage: feed.category?.id == category.id ? "checkmark" : "square")
                        }
                    }
                }
            } label: {
                Label("Move to Category", systemImage: "folder")
            }
        }
        .onAppear {
            // Diagnostic trail: a category-nested row logging
            // indent=0/compact=false means the stale-row bug is back.
            PrecisLogger.info("Row appeared: \(feed.title) indent=\(indent) compact=\(compact)")
        }
    }

    /// `reload: false` skips the full UI/library reload — refresh-all passes
    /// it for every feed and reloads ONCE at the end. Reloading per feed made
    /// a 400-feed pass rebuild the whole article library 400 times on the
    /// main thread (sampled: the main thread spent most of its time there).
    private func refreshSingleFeed(_ feed: FeedRecord, reload: Bool = true) async {
        importStatus = "Refreshing \(feed.title)…"
        importStatusKind = .neutral

        do {
            let feedURL = URL(string: feed.url) ?? URL(string: "https://example.com/feed.xml")!
            let parsed = try await FeedRefreshService().fetchAndParse(Feed(title: feed.title, url: feedURL))

            // Swap a URL/host placeholder name for the feed's real channel
            // title (e.g. "BBC Sport") — also backfills older imports
            let betterTitle = FeedDiscoveryService.displayTitle(current: feed.title, parsedTitle: parsed.title)
            if betterTitle != feed.title {
                feed.title = betterTitle
            }

            for entry in parsed.entries {
                let article = ArticleRecord(
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
                try ArticleRepository().saveIfNew(article, context: modelContext)
            }

            try FeedRepository().update(feed, context: modelContext)
            if reload {
                refreshFeeds()
            }
            importStatus = "\(feed.title) refreshed"
            importStatusKind = .success
        } catch {
            importStatus = "Refresh failed: \(error.localizedDescription)"
            importStatusKind = .error
        }
    }

    /// One-shot pass at launch: feeds imported before real channel titles were
    /// captured still store a URL/host as their name — fetch the feed and swap
    /// in its actual title (e.g. "BBC Sport" for feeds.bbci.co.uk/sport/rss.xml).
    private func repairURLTitledFeeds() async {
        let broken = importedFeeds.filter { FeedDiscoveryService.looksLikeURL($0.title) }
        guard !broken.isEmpty else { return }

        let service = FeedRefreshService()
        for feed in broken {
            guard let url = URL(string: feed.url),
                  let parsed = try? await service.fetchAndParse(Feed(title: feed.title, url: url))
            else { continue }

            let betterTitle = FeedDiscoveryService.displayTitle(current: feed.title, parsedTitle: parsed.title)
            if betterTitle != feed.title {
                feed.title = betterTitle
                try? modelContext.save()
            }
        }
        refreshFeeds()
    }

    private func refreshAllFeeds() async {
        isRefreshingAll = true
        for feed in importedFeeds {
            // No per-feed UI reload — reload once after the whole pass.
            await refreshSingleFeed(feed, reload: false)
        }
        refreshFeeds()
        isRefreshingAll = false
        importStatus = "All feeds refreshed"
        importStatusKind = .success
    }

    private func relativeTimeString(from date: Date) -> String {
        let delta = Int(Date().timeIntervalSince(date))
        if delta < 60 { return "now" }
        if delta < 3600 { return "\(delta / 60)m ago" }
        if delta < 86400 { return "\(delta / 3600)h ago" }
        return "\(delta / 86400)d ago"
    }

    // MARK: - OPML Import / Export

    private func importOPML() {
        let panel = NSOpenPanel()
        panel.title = "Import OPML"
        panel.allowedContentTypes = [.xml, .text, .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                do {
                    let opmlFeeds = try OPMLService.parse(contentsOf: url)
                    let feedRepository = FeedRepository()
                    let articleRepository = ArticleRepository()
                    let refreshService = FeedRefreshService()

                    var folderCache: [String: FolderRecord] = [:]

                    for opmlFeed in opmlFeeds {
                        // Resolve folder
                        var folderRecord: FolderRecord? = nil
                        if let folderName = opmlFeed.folderName {
                            if let cached = folderCache[folderName] {
                                folderRecord = cached
                            } else {
                                let folder = try FolderRepository().create(name: folderName, context: modelContext)
                                folderCache[folderName] = folder
                                folderRecord = folder
                            }
                        }

                        let feed = try feedRepository.create(
                            title: opmlFeed.title,
                            url: opmlFeed.url,
                            folder: folderRecord,
                            context: modelContext
                        )

                        // Fetch articles for each feed
                        if let feedURL = URL(string: opmlFeed.url) {
                            do {
                                let parsed = try await refreshService.fetchAndParse(
                                    Feed(title: opmlFeed.title, url: feedURL)
                                )
                                // Use the feed's real channel title when the
                                // OPML entry only carried a URL
                                let displayTitle = FeedDiscoveryService.displayTitle(current: feed.title, parsedTitle: parsed.title)
                                if displayTitle != feed.title {
                                    feed.title = displayTitle
                                    try modelContext.save()
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
                                    try articleRepository.saveIfNew(record, context: modelContext)
                                }
                            } catch {
                                // Skip feed if fetch fails — it's still imported
                            }
                        }
                    }

                    refreshFeeds()
                    importStatus = "Imported \(opmlFeeds.count) feeds from OPML"
                    importStatusKind = .success
                } catch {
                    importStatus = "OPML import failed: \(error.localizedDescription)"
                    importStatusKind = .error
                }
            }
        }
    }

    private func exportOPML() {
        let panel = NSSavePanel()
        panel.title = "Export OPML"
        panel.nameFieldStringValue = "Precis-Subscriptions.opml"
        panel.allowedContentTypes = [.xml, .data]

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            var opmlFeeds: [OPMLFeed] = []
            for feed in importedFeeds {
                opmlFeeds.append(OPMLFeed(
                    title: feed.title,
                    url: feed.url,
                    folderName: feed.folder?.name
                ))
            }

            let xml = OPMLService.generate(feeds: opmlFeeds)
            do {
                try xml.write(to: url, atomically: true, encoding: .utf8)
                importStatus = "Exported \(opmlFeeds.count) feeds"
                importStatusKind = .success
            } catch {
                importStatus = "Export failed: \(error.localizedDescription)"
                importStatusKind = .error
            }
        }
    }

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: { openWindow(id: "settings") }) {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundStyle(PrecisDesignSystem.marginalia)
                }
                .buttonStyle(.plain)
                .help("Settings")

                Button(action: { showAddFeedSheet = true }) {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .foregroundStyle(PrecisDesignSystem.marginalia)
                }
                .buttonStyle(.plain)
                .help("Add feed")

                Spacer()

                Button(action: { isSidebarHidden = true }) {
                    Image(systemName: "sidebar.left")
                        .font(.title3)
                        .foregroundStyle(PrecisDesignSystem.marginalia)
                }
                .buttonStyle(.plain)
                .help("Hide sidebar")

                Button(action: {
                    Task { await refreshAllFeeds() }
                }) {
                    if isRefreshingAll {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.title3)
                            .foregroundStyle(PrecisDesignSystem.marginalia)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isRefreshingAll)
                .help("Refresh all feeds")
            }
            .padding(PrecisSpacing.md)

            // Spacing 9 (was PrecisSpacing.sm = 12) + row padding 6 (was 8)
            // = 25% tighter vertical rhythm between sidebar items.
            VStack(alignment: .leading, spacing: 9) {
                // Library section
                SidebarSection(title: "Library")
                SidebarItem(title: "All Items", icon: "tray.full", badge: viewModel.totalUnreadCount, active: selectedSidebarItem == "All Items") {
                    selectedSidebarItem = "All Items"
                    viewModel.selectedSidebarFilter = .all
                }
                SidebarItem(title: "Unread", icon: "envelope.badge", badge: viewModel.totalUnreadCount, active: selectedSidebarItem == "Unread") {
                    selectedSidebarItem = "Unread"
                    viewModel.selectedSidebarFilter = .unread
                }
                SidebarItem(title: "Starred", icon: "star", badge: viewModel.totalStarredCount, active: selectedSidebarItem == "Starred") {
                    selectedSidebarItem = "Starred"
                    viewModel.selectedSidebarFilter = .starred
                }
            }
            .padding(.horizontal, PrecisSpacing.md)

            // Categories + feeds scroll lazily. With a 400-feed import this
            // content is thousands of rows tall: the old eager, non-scrolling
            // VStack laid out EVERY row on every render and clipped whatever
            // extended past the window edge — most feeds were unreachable.
            ScrollView {
            LazyVStack(alignment: .leading, spacing: 9) {
                // Categories section
                SidebarSection(title: "Categories", addActive: isAddingCategory) {
                    isAddingCategory.toggle()
                    newCategoryName = ""
                }

                if isAddingCategory {
                    TextField("", text: $newCategoryName, prompt: Text("Category name"))
                        .textFieldStyle(.roundedBorder)
                        .font(PrecisTypography.body)
                        .focused($isCategoryInputFocused)
                        .onSubmit { createCategory() }
                        .onExitCommand {
                            isAddingCategory = false
                            newCategoryName = ""
                        }
                        .onAppear {
                            DispatchQueue.main.async { isCategoryInputFocused = true }
                        }
                        .padding(.vertical, 4)
                }

                ForEach(categories) { category in
                    if editingCategoryID == category.id {
                        TextField("", text: $editingCategoryName, prompt: Text("Category name"))
                            .textFieldStyle(.roundedBorder)
                            .font(PrecisTypography.body)
                            .focused($isCategoryEditFocused)
                            .onSubmit { commitCategoryRename() }
                            .onExitCommand { cancelCategoryRename() }
                            .onChange(of: isCategoryEditFocused) { _, focused in
                                if !focused && editingCategoryID != nil {
                                    commitCategoryRename()
                                }
                            }
                            .padding(.vertical, 4)
                    } else {
                        let isCategorySelected = selectedSidebarItem == category.name
                        HStack(spacing: 10) {
                            if isCategorySelected {
                                Capsule()
                                    .frame(width: 4, height: 18)
                                    .foregroundStyle(Color.accentColor)
                            } else {
                                Color.clear
                                    .frame(width: 4, height: 18)
                            }

                            Image(systemName: "square.grid.2x2")
                                .font(.body)
                                .frame(width: 18)
                                .foregroundStyle(isCategorySelected ? Color.accentColor : PrecisDesignSystem.foreground(for: colorScheme).opacity(0.6))

                            Text(category.name)
                                .font(PrecisTypography.body)
                                .fontWeight(isCategorySelected ? .semibold : nil)
                                .foregroundStyle(isCategorySelected ? Color.accentColor : PrecisDesignSystem.foreground(for: colorScheme).opacity(0.75))

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Show only the feeds indented under this category;
                            // the view model merges and sorts them across feeds.
                            selectedSidebarItem = category.name
                            viewModel.selectedSidebarFilter = .category(category.id)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    categoryDropTargetID == category.id
                                        ? PrecisDesignSystem.flag.opacity(0.15)
                                        : Color.clear
                                )
                        )
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { height in
                            categoryRowHeights[category.id] = height
                        }
                        .draggable(category.id.uuidString) {
                            HStack(spacing: 8) {
                                Image(systemName: "square.grid.2x2")
                                    .foregroundStyle(PrecisDesignSystem.flag)
                                Text(category.name)
                                    .font(PrecisTypography.body)
                                    .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .dropDestination(for: String.self) { items, location in
                            guard let first = items.first,
                                  let sourceID = UUID(uuidString: first),
                                  categories.contains(where: { $0.id == sourceID })
                            else { return false }

                            // Half-test midpoint; fall back to a typical row
                            // height if geometry capture hasn't reported yet.
                            let height = categoryRowHeights[category.id] ?? 0
                            let midY = height > 0 ? height / 2 : 18
                            let insertAfter = location.y >= midY
                            categoryDropTargetID = nil
                            PrecisLogger.info("Category drop: \(sourceID.uuidString.prefix(8)) → \(category.id.uuidString.prefix(8)) after=\(insertAfter)")
                            moveCategory(sourceID: sourceID, targetID: category.id, insertAfter: insertAfter)
                            return true
                        } isTargeted: { targeted in
                            if targeted {
                                categoryDropTargetID = category.id
                            } else if categoryDropTargetID == category.id {
                                categoryDropTargetID = nil
                            }
                        }
                        .help("Drag to reorder")
                        .contextMenu {
                            Button {
                                beginEditingCategory(category)
                            } label: {
                                Label("Rename…", systemImage: "pencil")
                            }
                            Divider()
                            Button {
                                ungroupFeeds(feeds(in: category))
                            } label: {
                                Label("Remove from Category", systemImage: "folder.badge.minus")
                            }
                            .disabled(feeds(in: category).isEmpty)
                            Button(role: .destructive) {
                                feedsPendingDeletion = feeds(in: category)
                            } label: {
                                Label("Delete All Feeds in Category", systemImage: "trash")
                            }
                            .disabled(feeds(in: category).isEmpty)
                            Divider()
                            Button(role: .destructive) {
                                deleteCategory(category)
                            } label: {
                                Label("Delete Category", systemImage: "trash")
                            }
                        }
                    }

                    // Feeds moved into this category, indented beneath it.
                    //
                    // The `.id()` keys are load-bearing: when a feed moves
                    // between sections the lazy stack tried to keep the old
                    // row instance at its new position — frozen with the
                    // previous section's parameters (no indent, timestamp
                    // visible) and ignoring selection-state repaints. Keying
                    // on section + feed + checked forces a fresh row whenever
                    // any of those change.
                    let categoryFeeds = feeds(in: category)
                    ForEach(categoryFeeds) { feed in
                        sidebarFeedRow(feed, indent: 32, compact: true, group: categoryFeeds)
                            .id("cat-\(category.id)-\(feed.id)-\(selectedFeedIDs.contains(feed.id))")
                    }
                }

                // Feeds not assigned to a category
                if !uncategorizedFeeds.isEmpty {
                    SidebarSection(title: "Feeds")
                }

                ForEach(uncategorizedFeeds) { feed in
                    sidebarFeedRow(feed, group: uncategorizedFeeds)
                        .id("uncat-\(feed.id)-\(selectedFeedIDs.contains(feed.id))")
                }
            }
            .padding(.horizontal, PrecisSpacing.md)
            }

            // Action bar — appears as soon as any feed is checked, so the
            // flow (tick boxes → Delete) is visible with zero chrome when
            // nothing is selected and no keyboard knowledge required.
            if !selectedFeedIDs.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)

                    Text("\(selectedFeedIDs.count) selected")
                        .font(PrecisTypography.caption)
                        .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))

                    Spacer()

                    Button {
                        selectedFeedIDs.removeAll()
                    } label: {
                        Text("Clear")
                            .font(PrecisTypography.caption)
                            .foregroundStyle(PrecisDesignSystem.marginalia)
                    }
                    .buttonStyle(.plain)

                    Button {
                        beginBulkDelete()
                    } label: {
                        Text(selectedFeedIDs.count == 1 ? "Delete" : "Delete \(selectedFeedIDs.count)")
                            .font(PrecisTypography.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.red, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Delete the checked feeds after confirmation")
                }
                .padding(.horizontal, PrecisSpacing.md)
                .padding(.vertical, 8)
            }
        }
        .background(colorScheme == .dark ? PrecisDesignSystem.surface(for: colorScheme) : Color.white)
        // Key focus for the Delete-key shortcut; focus follows the checks
        // (armed in toggleFeedChecked / the Shift-range branch) and the
        // focus ring stays suppressed.
        .focusable()
        .focused($sidebarFocused)
        .focusEffectDisabled(true)
        .onKeyPress(.delete) {
            guard !selectedFeedIDs.isEmpty else { return .ignored }
            beginBulkDelete()
            return .handled
        }
        .sheet(isPresented: $showAddFeedSheet) {
            AddFeedSheet(
                feedURLInput: $feedURLInput,
                isImporting: $isImporting,
                importStatus: $importStatus,
                importStatusKind: $importStatusKind,
                onAdd: {
                    Task {
                        isImporting = true
                        importStatus = ""
                        importStatusKind = .neutral
                        do {
                            let before = (try? ArticleRepository().fetchAll(context: modelContext).count) ?? 0
                            try await viewModel.importFeed(from: feedURLInput, in: modelContext)
                            refreshFeeds()
                            viewModel.selectedSidebarFilter = .all
                            viewModel.loadArticles(for: nil, context: modelContext)
                            let after = (try? ArticleRepository().fetchAll(context: modelContext).count) ?? 0
                            let added = max(0, after - before)
                            // Stay open so several feeds can be added back-to-
                            // back; "Done" (or the ✕) closes the sheet.
                            importStatus = added > 0
                                ? "Added \(added) new article\(added == 1 ? "" : "s") — paste another URL to add the next feed"
                                : "Feed added — no new articles yet; paste another URL to add the next feed"
                            importStatusKind = .success
                            feedURLInput = ""
                        } catch {
                            importStatus = "Could not import feed: \(error.localizedDescription)"
                            importStatusKind = .error
                        }
                        isImporting = false
                    }
                }
            )
        }
        // Favicon loading moved into `FeedFaviconView` itself: the old
        // warm-up loop wrote into a `@State` dictionary once PER feed, so
        // each arrival re-rendered the whole window (sidebar + list + pane)
        // — 400 times on launch, each pass rebuilding every sidebar row.
        .alert(
            feedsPendingDeletion.count > 1
                ? "Delete \(feedsPendingDeletion.count) Feeds?"
                : "Delete Feed?",
            isPresented: Binding(
                get: { !feedsPendingDeletion.isEmpty },
                set: { if !$0 { feedsPendingDeletion = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deletePendingFeeds()
            }
            Button("Cancel", role: .cancel) {
                feedsPendingDeletion = []
            }
        } message: {
            if feedsPendingDeletion.count > 1 {
                Text("These \(feedsPendingDeletion.count) feeds and all of their articles will be permanently deleted. This cannot be undone.")
            } else if let feed = feedsPendingDeletion.first {
                Text("\"\(feed.title)\" and all of its articles will be permanently removed. This cannot be undone.")
            }
        }
    }

}

// MARK: - Add Feed Sheet

private struct AddFeedSheet: View {
    @Binding var feedURLInput: String
    @Binding var isImporting: Bool
    @Binding var importStatus: String
    @Binding var importStatusKind: ImportStatusKind
    let onAdd: () -> Void
    @State private var didImport = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isURLEntryFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PrecisSpacing.md) {
            HStack {
                Text("Add Feed")
                    .font(PrecisTypography.headline)
                    .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(PrecisDesignSystem.marginalia.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            Text("Paste a URL — supports RSS, YouTube, Reddit, Google News, X, Facebook, Bluesky, GitHub, TikTok, and more")
                .font(PrecisTypography.metadata)
                .foregroundStyle(PrecisDesignSystem.marginalia)

            TextField("", text: $feedURLInput, prompt: isURLEntryFocused
                ? nil
                : Text("https://example.com/feed.xml or any supported URL"))
                .textFieldStyle(.roundedBorder)
                .font(PrecisTypography.body)
                .focused($isURLEntryFocused)
                .onSubmit { onAdd() }

            HStack(spacing: 12) {
                Button(action: onAdd) {
                    HStack {
                        if isImporting {
                            ProgressView()
                                .frame(width: 12, height: 12)
                        }
                        Text(isImporting ? "Importing..." : "Add Feed")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isImporting || feedURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                // Appears after the first successful import so further feeds
                // can be added in the same session; closes the sheet.
                if didImport {
                    Button(action: { dismiss() }) {
                        Text("Done")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isImporting)
                }
            }

            if !importStatus.isEmpty {
                Text(importStatus)
                    .font(PrecisTypography.metadata)
                    .foregroundStyle(importStatusKind == .success ? Color.accentColor : (importStatusKind == .error ? .red : PrecisDesignSystem.marginalia))
                    .lineLimit(2)
            }
        }
        .padding(PrecisSpacing.lg)
        .frame(width: 420)
        .onAppear {
            // Fresh sheet state on every presentation.
            importStatus = ""
            importStatusKind = .neutral
            didImport = false
        }
        .onChange(of: importStatusKind) { _, kind in
            if kind == .success {
                didImport = true
                // Ready the field for the next feed URL.
                isURLEntryFocused = true
            }
        }
    }
}

// MARK: - Feed Favicon View

private struct FeedFaviconView: View {
    let url: String
    /// Each row owns its fetch and its decoded image: the row re-renders
    /// itself once when the icon arrives instead of invalidating a shared
    /// dictionary that re-rendered every row in the sidebar. The decoded
    /// `NSImage` is also held here — the old code re-ran `NSImage(data:)`
    /// for every row on every sidebar render.
    @State private var nsImage: NSImage?

    var body: some View {
        Group {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "rss")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(PrecisDesignSystem.flag)
            }
        }
        .frame(width: 16, height: 16)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .task(id: url) {
            guard nsImage == nil else { return }
            guard let data = await FaviconService.favicon(for: url),
                  let image = NSImage(data: data) else { return }
            nsImage = image
        }
    }
}

private enum ImportStatusKind {
    case neutral
    case success
    case error
}

private struct SidebarSection: View {
    let title: String
    var addActive: Bool = false
    var onAdd: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHoveringAdd = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(PrecisTypography.caption)
                .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.6))
                .textCase(.uppercase)
                .tracking(1.2)

            Spacer(minLength: 0)

            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        // Solid accent plus over a light, fairly transparent
                        // accent wash so the + still stands out.
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20, height: 20)
                        .background(
                            Circle()
                                .fill(Color.accentColor.opacity(isHoveringAdd ? 0.24 : 0.12))
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(Color.accentColor.opacity(isHoveringAdd ? 0.55 : 0.30), lineWidth: 1)
                        )
                        .rotationEffect(.degrees(addActive ? 45 : 0))
                        .scaleEffect(isHoveringAdd ? 1.08 : 1)
                }
                .buttonStyle(.plain)
                .onHover { isHoveringAdd = $0 }
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: addActive)
                .animation(.easeOut(duration: 0.15), value: isHoveringAdd)
                .help(addActive ? "Cancel" : "New category")
            }
        }
        .padding(.top, PrecisSpacing.sm)
    }
}

private struct SidebarItem: View {
    let title: String
    var icon: String? = nil
    var badge: Int = 0
    let active: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if active {
                    Capsule()
                        .frame(width: 4, height: 18)
                        // Short indicator bar beside the active sidebar item.
                        .foregroundStyle(Color.accentColor)
                } else {
                    Color.clear
                        .frame(width: 4, height: 18)
                }

                if let icon {
                    Image(systemName: icon)
                        .font(.body)
                        .frame(width: 18)
                        .foregroundStyle(active ? PrecisDesignSystem.flag : PrecisDesignSystem.foreground(for: colorScheme).opacity(0.6))
                }

                Text(title)
                    .font(PrecisTypography.body)
                    .foregroundStyle(active ? PrecisDesignSystem.foreground(for: colorScheme) : PrecisDesignSystem.foreground(for: colorScheme).opacity(0.75))

                Spacer()

                if badge > 0 {
                    Text("\(badge)")
                        .font(PrecisTypography.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(active ? PrecisDesignSystem.surface(for: colorScheme).opacity(0.8) : Color.clear)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

private struct ArticleRow: View {
    let title: String
    let meta: String
    let unread: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                if unread {
                    Circle()
                        .frame(width: 8, height: 8)
                        .foregroundStyle(PrecisDesignSystem.flag)
                }

                Text(title)
                    .font(PrecisTypography.headline)
                    .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))
                    .lineLimit(2)
            }

            Text(meta)
                .font(PrecisTypography.metadata)
                .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.6))
        }
        .padding(PrecisSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(unread ? PrecisDesignSystem.surface(for: colorScheme) : Color.clear)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(PrecisDesignSystem.rule(for: colorScheme))
                .padding(.horizontal, 0),
            alignment: .bottom
        )
    }
}

#Preview {
    MainWindowLayout()
}

// MARK: - Resizable Divider

private struct ResizableDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            // Always the neutral rule color — hover only changes the cursor.
            .fill(PrecisDesignSystem.rule(for: colorScheme))
            .frame(height: 4)
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

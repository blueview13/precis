import SwiftUI
import AppKit
import Combine

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
    @State private var refreshingFeedID: UUID?
    @State private var importStatus = ""
    @State private var importStatusKind: ImportStatusKind = .neutral
    @State private var importedFeeds: [FeedRecord] = []
    @State private var showAddFeedSheet = false
    @State private var faviconCache: [String: Data] = [:]
    @State private var articleListHeight: CGFloat = 350
    @State private var sidebarWidth: CGFloat = 260
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
            sidebarView
                .frame(width: sidebarWidth)

            // Draggable vertical divider for sidebar resize
            Rectangle()
                .fill(Color.clear)
                .frame(width: 6)
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
                ArticleListView(viewModel: viewModel)
                    .frame(height: articleListHeight)

                ResizableDivider()
                    .frame(height: 4)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let newHeight = articleListHeight + value.translation.height
                                let maxHeight = NSScreen.main?.frame.height ?? 900
                                articleListHeight = max(150, min(newHeight, maxHeight * 0.6))
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
            viewModel.loadFromContext(modelContext)
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

    private func refreshSingleFeed(_ feed: FeedRecord) async {
        refreshingFeedID = feed.id
        importStatus = "Refreshing \(feed.title)…"
        importStatusKind = .neutral

        do {
            let feedURL = URL(string: feed.url) ?? URL(string: "https://example.com/feed.xml")!
            let parsed = try await FeedRefreshService().fetchAndParse(Feed(title: feed.title, url: feedURL))

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
            refreshFeeds()
            importStatus = "\(feed.title) refreshed"
            importStatusKind = .success
        } catch {
            importStatus = "Refresh failed: \(error.localizedDescription)"
            importStatusKind = .error
        }

        refreshingFeedID = nil
    }

    private func refreshAllFeeds() async {
        isRefreshingAll = true
        for feed in importedFeeds {
            await refreshSingleFeed(feed)
        }
        isRefreshingAll = false
        importStatus = "All feeds refreshed"
        importStatusKind = .success
    }

    private func relativeTimeString(from date: Date) -> String {
        let delta = Int(Date().timeIntervalSince(date))
        if delta < 60 { return "just now" }
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

                Button(action: { showAddFeedSheet = true }) {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .foregroundStyle(PrecisDesignSystem.marginalia)
                }
                .buttonStyle(.plain)

                Spacer()

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
            }
            .padding(PrecisSpacing.md)

            VStack(alignment: .leading, spacing: PrecisSpacing.sm) {
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
                SidebarItem(title: "Starred", icon: "star", active: selectedSidebarItem == "Starred") {
                    selectedSidebarItem = "Starred"
                    viewModel.selectedSidebarFilter = .starred
                }
                SidebarItem(title: "Later", icon: "clock.arrow.circlepath", active: selectedSidebarItem == "Later") {
                    selectedSidebarItem = "Later"
                    viewModel.selectedSidebarFilter = .later
                }

                // Feeds
                if !importedFeeds.isEmpty {
                    SidebarSection(title: "Feeds")
                }

                ForEach(importedFeeds) { feed in
                    HStack {
                        Button(action: {
                            viewModel.loadArticles(for: feed.id, context: modelContext)
                            viewModel.selectedSidebarFilter = .feed(feed.id)
                            selectedSidebarItem = feed.title
                        }) {
                            HStack(spacing: 8) {
                                FeedFaviconView(url: feed.url, faviconCache: $faviconCache)
                                    .frame(width: 16, height: 16)
                                Text(feed.title)
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
                                .background(PrecisDesignSystem.flag)
                                .clipShape(Capsule())
                        }

                        Spacer()

                        if let lastFetched = feed.lastFetched {
                            Text(relativeTimeString(from: lastFetched))
                                .font(PrecisTypography.caption)
                                .foregroundStyle(PrecisDesignSystem.marginalia.opacity(0.7))
                        }

                        Button(action: {
                            Task { await refreshSingleFeed(feed) }
                        }) {
                            if refreshingFeedID == feed.id {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                                    .foregroundStyle(PrecisDesignSystem.marginalia)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(refreshingFeedID != nil)

                        Button(action: {
                            do {
                                try FeedRepository().delete(feed, context: modelContext)
                                refreshFeeds()
                                importStatus = "\(feed.title) removed"
                                importStatusKind = .neutral
                            } catch {
                                importStatus = "Could not remove feed"
                                importStatusKind = .error
                            }
                        }) {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, PrecisSpacing.md)

            Spacer(minLength: 0)
        }
        .background(PrecisDesignSystem.surface(for: colorScheme))
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
                            try await viewModel.importFeed(from: feedURLInput, in: modelContext)
                            refreshFeeds()
                            viewModel.selectedSidebarFilter = .all
                            viewModel.loadArticles(for: nil, context: modelContext)
                            let count = viewModel.items.count
                            importStatus = "Imported \(count) articles"
                            importStatusKind = .success
                            feedURLInput = ""
                            showAddFeedSheet = false
                        } catch {
                            importStatus = "Could not import feed: \(error.localizedDescription)"
                            importStatusKind = .error
                        }
                        isImporting = false
                    }
                }
            )
        }
        .onAppear {
            // Load favicons for all feeds
            Task {
                for feed in importedFeeds {
                    if faviconCache[feed.url] == nil {
                        if let data = await FaviconService.favicon(for: feed.url) {
                            faviconCache[feed.url] = data
                        }
                    }
                }
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

            if !importStatus.isEmpty {
                Text(importStatus)
                    .font(PrecisTypography.metadata)
                    .foregroundStyle(importStatusKind == .success ? PrecisDesignSystem.flag : (importStatusKind == .error ? .red : PrecisDesignSystem.marginalia))
                    .lineLimit(2)
            }
        }
        .padding(PrecisSpacing.lg)
        .frame(width: 420)
    }
}

// MARK: - Feed Favicon View

private struct FeedFaviconView: View {
    let url: String
    @Binding var faviconCache: [String: Data]

    var body: some View {
        Group {
            if let data = faviconCache[url], let nsImage = NSImage(data: data) {
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
    }
}

private enum ImportStatusKind {
    case neutral
    case success
    case error
}

private struct SidebarSection: View {
    let title: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(title)
            .font(PrecisTypography.caption)
            .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.6))
            .textCase(.uppercase)
            .tracking(1.2)
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
                        .foregroundStyle(PrecisDesignSystem.flag)
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
                        .background(PrecisDesignSystem.flag)
                        .clipShape(Capsule())
                }
            }
            .padding(.vertical, 8)
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
    @State private var isHovering = false

    var body: some View {
        Rectangle()
            .fill(isHovering ? PrecisDesignSystem.flag : PrecisDesignSystem.rule(for: colorScheme))
            .frame(height: 4)
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

import SwiftUI
import SwiftData
import AppKit

@main
struct PrecisApp: App {
    @AppStorage(PrecisTheme.storageKey) private var selectedThemeRawValue = PrecisTheme.standard.rawValue

    private let modelContainer: ModelContainer = {
        do {
            return try ModelContainerProvider.makeContainer()
        } catch {
            fatalError("Unable to create the model container: \(error)")
        }
    }()

    private var selectedTheme: PrecisTheme {
        PrecisTheme(rawValue: selectedThemeRawValue) ?? .standard
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            MainWindowLayout()
                .modelContainer(modelContainer)
                .preferredColorScheme(selectedTheme.colorScheme)
                .tint(selectedTheme.accent)
                .onAppear {
                    DesktopFeedPanelController.shared.install(modelContainer: modelContainer)
                }
        }

        Window("Settings", id: "settings") {
            SettingsView(
                onImportOPML: nil,
                onExportOPML: nil,
                hasFeeds: false
            )
            .modelContainer(modelContainer)
            .frame(width: 480, height: 560)
            .preferredColorScheme(selectedTheme.colorScheme)
            .tint(selectedTheme.accent)
        }
        .defaultSize(width: 480, height: 560)
        .commands {
            // Settings… in the Precis app menu (⌘,)
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .precisOpenSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    /// Posted by the app menu's Settings command. The main window observes it
    /// and calls its `openWindow` action (commands have no window environment).
    static let precisOpenSettings = Notification.Name("PrecisOpenSettings")
    /// Posted after an OPML import completes in the Settings window so the
    /// main window reloads its sidebar feed list.
    static let precisFeedsImported = Notification.Name("PrecisFeedsImported")
    static let precisOpenArticle = Notification.Name("PrecisOpenArticle")
    static let precisFeedsRefreshed = Notification.Name("PrecisFeedsRefreshed")
}

@MainActor
final class DesktopFeedPanelController: NSObject {
    static let shared = DesktopFeedPanelController()

    var onOpenArticle: ((UUID) -> Void)?

    private var modelContainer: ModelContainer?
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?

    func install(modelContainer: ModelContainer) {
        guard self.modelContainer == nil else { return }
        self.modelContainer = modelContainer
        AppScopedFeedRefreshCoordinator.shared.start(modelContainer: modelContainer)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesChanged),
            name: UserDefaults.didChangeNotification,
            object: UserDefaults.standard
        )
        preferencesChanged()
    }

    @objc private func preferencesChanged() {
        if UserDefaults.standard.bool(forKey: "desktopPanelEnabled") {
            if statusItem == nil {
                let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                let icon = NSImage(named: NSImage.Name("DesktopPanelIcon"))
                icon?.isTemplate = true
                icon?.size = NSSize(width: 18, height: 18)
                icon?.accessibilityDescription = "Precis headlines"
                statusItem.button?.image = icon
                statusItem.button?.toolTip = "Precis Headlines"
                statusItem.button?.target = self
                statusItem.button?.action = #selector(togglePanel)
                self.statusItem = statusItem
            }
            if panel?.isVisible == true {
                positionPanel()
            }
        } else {
            hidePanel()
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
        }
    }

    @objc private func togglePanel() {
        if panel?.isVisible == true {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let modelContainer else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let frame = panelFrame(on: screen)

        if panel == nil {
            let panel = NSPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.contentView = NSHostingView(
                rootView: DesktopFeedPanelView(
                    onOpenArticle: { [weak self] articleID in self?.onOpenArticle?(articleID) },
                    onClose: { [weak self] in self?.hidePanel() }
                )
                .modelContainer(modelContainer)
            )
            self.panel = panel
        }

        panel?.setFrame(frame, display: true)
        panel?.orderFrontRegardless()
    }

    private func positionPanel() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        panel?.setFrame(panelFrame(on: screen), display: true)
    }

    private func panelFrame(on screen: NSScreen) -> NSRect {
        let width = CGFloat(UserDefaults.standard.double(forKey: "desktopPanelWidth"))
            .clamped(to: 240...480, defaultValue: 320)
        let edge = UserDefaults.standard.string(forKey: "desktopPanelEdge") ?? "right"
        return DesktopPanelPlacement.frame(in: screen.visibleFrame, edge: edge, width: width)
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }

    @objc private func screenParametersChanged() {
        positionPanel()
    }
}

enum DesktopPanelFeedSelection {
    static func selectedFeedIDs(from storedValue: String, availableFeedIDs: Set<UUID>) -> Set<UUID> {
        if storedValue == "*" { return availableFeedIDs }
        if storedValue == "none" { return [] }
        return Set(storedValue.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
            .intersection(availableFeedIDs)
    }

    static func storedValue(for selectedFeedIDs: Set<UUID>, availableFeedIDs: Set<UUID>) -> String {
        if selectedFeedIDs.isEmpty { return "none" }
        if selectedFeedIDs == availableFeedIDs { return "*" }
        return selectedFeedIDs.map(\.uuidString).sorted().joined(separator: ",")
    }
}

enum DesktopPanelPlacement {
    static func frame(in visibleFrame: CGRect, edge: String, width: CGFloat) -> CGRect {
        let panelWidth = width.clamped(to: 240...480, defaultValue: 320)
        let x = edge == "left" ? visibleFrame.minX : visibleFrame.maxX - panelWidth
        return CGRect(x: x, y: visibleFrame.minY, width: panelWidth, height: visibleFrame.height)
    }
}

@MainActor
final class AppScopedFeedRefreshCoordinator: NSObject {
    static let shared = AppScopedFeedRefreshCoordinator()

    private let refreshService = BackgroundRefreshService()
    private var modelContainer: ModelContainer?
    private var scheduledIntervalMinutes: Int?
    private var isRefreshing = false

    func beginManualRefresh() -> Bool {
        guard !isRefreshing else { return false }
        isRefreshing = true
        return true
    }

    func endManualRefresh() {
        isRefreshing = false
    }

    func start(modelContainer: ModelContainer) {
        guard self.modelContainer == nil else { return }
        self.modelContainer = modelContainer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesChanged),
            name: UserDefaults.didChangeNotification,
            object: UserDefaults.standard
        )
        scheduleRefresh()
    }

    @objc private func preferencesChanged() {
        let intervalMinutes = UserDefaults.standard.object(forKey: "refreshIntervalMinutes") as? Int ?? 15
        guard intervalMinutes != scheduledIntervalMinutes else { return }
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        let intervalMinutes = UserDefaults.standard.object(forKey: "refreshIntervalMinutes") as? Int ?? 15
        let interval = RefreshInterval(rawValue: intervalMinutes) ?? .fifteenMinutes
        scheduledIntervalMinutes = intervalMinutes
        refreshService.stopRefreshLoop()
        refreshService.beginRefreshLoop(interval: interval) { [weak self] in
            await self?.refreshAllFeeds()
        }
    }

    private func refreshAllFeeds() async {
        guard !isRefreshing, let context = modelContainer?.mainContext else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let feeds = try FeedRepository().fetchAll(context: context)
            let articleRepository = ArticleRepository()
            let feedRepository = FeedRepository()
            var newArticleCount = 0
            var refreshedFeedNames: [String] = []

            for feed in feeds {
                guard let url = URL(string: feed.url) else { continue }
                do {
                    let parsed = try await FeedRefreshService().fetchAndParse(Feed(title: feed.title, url: url))
                    let betterTitle = FeedDiscoveryService.displayTitle(current: feed.title, parsedTitle: parsed.title)
                    if betterTitle != feed.title {
                        feed.title = betterTitle
                    }

                    var feedNewArticleCount = 0
                    for entry in parsed.entries {
                        let article = ArticleRecord(
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
                        if try articleRepository.saveIfNew(article, context: context) {
                            feedNewArticleCount += 1
                        }
                    }

                    try feedRepository.update(feed, context: context)
                    newArticleCount += feedNewArticleCount
                    if feedNewArticleCount > 0 {
                        refreshedFeedNames.append(feed.sidebarTitle ?? feed.title)
                    }
                } catch {
                    PrecisLogger.error("Scheduled refresh failed for \(feed.title): \(error.localizedDescription)")
                }
            }

            NotificationCenter.default.post(name: .precisFeedsRefreshed, object: nil)
            if UserDefaults.standard.bool(forKey: "notifyOnNewArticles"), newArticleCount > 0 {
                try? await NewArticleNotificationService.sendNewArticlesNotification(
                    count: newArticleCount,
                    feedNames: refreshedFeedNames
                )
            }
        } catch {
            PrecisLogger.error("Scheduled feed refresh failed: \(error.localizedDescription)")
        }
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>, defaultValue: CGFloat) -> CGFloat {
        self == 0 ? defaultValue : Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private struct DesktopFeedPanelView: View {
    @Query(sort: \ArticleRecord.publishedDate, order: .reverse)
    private var articles: [ArticleRecord]
    @AppStorage("desktopPanelSources") private var selectedFeedIDs = "*"
    @AppStorage("desktopPanelWidth") private var panelWidth = 320.0
    @AppStorage("desktopPanelBackground") private var backgroundHex = "#FFBE24"
    @AppStorage("desktopPanelOpacity") private var backgroundOpacity = 0.35

    let onOpenArticle: (UUID) -> Void
    let onClose: () -> Void

    private var visibleArticles: [ArticleRecord] {
        let availableFeedIDs = Set(articles.compactMap { $0.feed?.id })
        let selection = DesktopPanelFeedSelection.selectedFeedIDs(
            from: selectedFeedIDs,
            availableFeedIDs: availableFeedIDs
        )

        return Array(articles.lazy.filter { article in
            guard let feed = article.feed, !feed.muted else { return false }
            return selection.contains(feed.id)
        }.prefix(80))
    }

    private var panelBackground: Color {
        PrecisDesignSystem.color(hex: backgroundHex) ?? PrecisTheme.current.background
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: PrecisSpacing.sm) {
                Image("DesktopPanelIcon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(PrecisDesignSystem.marginalia)
                Text("Precis")
                    .font(PrecisTypography.headline)
                    .foregroundStyle(PrecisDesignSystem.foreground(for: .light))
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Hide headlines")
            }
            .padding(.horizontal, PrecisSpacing.md)
            .padding(.vertical, PrecisSpacing.sm)

            Divider()
                .overlay(PrecisDesignSystem.rule(for: .light))

            ScrollView {
                LazyVStack(spacing: 0) {
                    if visibleArticles.isEmpty {
                        Text("No articles to show")
                            .font(PrecisTypography.body)
                            .foregroundStyle(PrecisDesignSystem.foreground(for: .light).opacity(0.65))
                            .frame(maxWidth: .infinity, minHeight: 100)
                    } else {
                        ForEach(visibleArticles) { article in
                            Button {
                                onOpenArticle(article.id)
                            } label: {
                                articleRow(article)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open \(article.title) from \(article.feed?.title ?? "feed")")

                            Divider()
                                .overlay(PrecisDesignSystem.rule(for: .light))
                        }
                    }
                }
                .padding(.horizontal, PrecisSpacing.md)
            }
        }
        .frame(width: CGFloat(panelWidth).clamped(to: 240...480, defaultValue: 320))
        .background(panelBackground.opacity(backgroundOpacity))
        .environment(\.colorScheme, PrecisTheme.current.colorScheme)
    }

    private func articleRow(_ article: ArticleRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(article.feed?.title ?? "Feed")
                    .font(PrecisTypography.caption)
                    .foregroundStyle(PrecisDesignSystem.marginalia)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !article.isRead {
                    Circle()
                        .fill(PrecisDesignSystem.flag)
                        .frame(width: 6, height: 6)
                        .accessibilityLabel("Unread")
                }
            }

            Text(article.title)
                .font(PrecisTypography.body.weight(article.isRead ? .regular : .semibold))
                .foregroundStyle(PrecisDesignSystem.foreground(for: .light))
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(article.summary?.shortText ?? excerpt(for: article))
                .font(PrecisTypography.caption)
                .foregroundStyle(PrecisDesignSystem.foreground(for: .light).opacity(0.72))
                .multilineTextAlignment(.leading)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, PrecisSpacing.sm)
        .contentShape(Rectangle())
    }

    private func excerpt(for article: ArticleRecord) -> String {
        let rawText = article.normalizedText
            ?? article.extractedContentText
            ?? article.rawContentText
            ?? article.title
        return rawText
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

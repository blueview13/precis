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
            CommandGroup(after: .newItem) {
                Button("New Smart Category…") {
                    NotificationCenter.default.post(name: .precisNewSmartCategory, object: nil)
                }
                Button("Choose Smart Category Sync Folder…") {
                    SmartCategoryStore.shared.chooseSyncFolder()
                }
            }
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
    /// Posted by the headlines panel when an article is opened, so the main
    /// window's list can mirror the read state without re-fetching everything.
    static let precisArticleRead = Notification.Name("PrecisArticleRead")
    static let precisFeedsRefreshed = Notification.Name("PrecisFeedsRefreshed")
    static let precisNewSmartCategory = Notification.Name("PrecisNewSmartCategory")
}

@MainActor
final class DesktopFeedPanelController: NSObject {
    static let shared = DesktopFeedPanelController()

    private var modelContainer: ModelContainer?
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    /// Last `desktopPanelEnabled` value seen by `preferencesChanged`, so an
    /// off→on change (the user ticking the box) can open the panel while the
    /// initial call from `install` leaves it closed behind its menu bar icon.
    private var wasEnabled: Bool?

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
        let enabled = UserDefaults.standard.bool(forKey: "desktopPanelEnabled")
        let previouslyEnabled = wasEnabled
        wasEnabled = enabled
        if enabled {
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
            if previouslyEnabled == false {
                // Just ticked in Settings — open the panel straight away
                // instead of leaving it to a menu bar click.
                showPanel()
            } else if panel?.isVisible == true {
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
            // Hover tracking drives the ←→ cursor on the resize strip, and
            // borderless panels don't take mouse-moved events by default —
            // without this the strip's onHover never fires.
            panel.acceptsMouseMovedEvents = true
            panel.contentView = PanelHostingView(
                rootView: DesktopFeedPanelView(
                    onClose: { [weak self] in self?.hidePanel() },
                    onResize: { [weak self] width in self?.resizePanel(to: width) }
                )
                .modelContainer(modelContainer)
            )
            self.panel = panel
        }

        panel?.setFrame(frame, display: true)
        panel?.orderFrontRegardless()
    }

    private func positionPanel() {
        // Stay on the screen the panel is already on: the drag handle resizes
        // it in place, and NSScreen.main follows the key window, which is the
        // main reader — not this panel, which can never become key.
        guard let screen = panel?.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        panel?.setFrame(panelFrame(on: screen), display: true)
    }

    /// Applies a width from the panel's drag handle. Stored so it survives
    /// relaunch — the Settings slider that used to own this is gone — and
    /// applied immediately so the window tracks the drag.
    private func resizePanel(to width: CGFloat) {
        let clampedWidth = DesktopPanelPlacement.width(fromStoredWidth: width)
        UserDefaults.standard.set(Double(clampedWidth), forKey: "desktopPanelWidth")
        positionPanel()
    }

    private func panelFrame(on screen: NSScreen) -> NSRect {
        let width = UserDefaults.standard.double(forKey: "desktopPanelWidth")
        let edge = UserDefaults.standard.string(forKey: "desktopPanelEdge") ?? "right"
        return DesktopPanelPlacement.frame(in: screen.visibleFrame, edge: edge, width: CGFloat(width))
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
    /// Widths the panel can take — the drag handle and the stored value both
    /// clamp here.
    static let widthRange: ClosedRange<CGFloat> = 240...480
    /// Width a fresh install opens at, and the fallback whenever the stored
    /// value is missing (or zero, which is what a missing value reads as).
    static let defaultWidth: CGFloat = 300

    /// The stored width, clamped into range; zero means "never set".
    static func width(fromStoredWidth storedWidth: CGFloat) -> CGFloat {
        storedWidth.clamped(to: widthRange, defaultValue: defaultWidth)
    }

    /// Width while the inner edge is dragged. The edge facing the screen
    /// interior grows the panel as it is pulled away from the docked edge.
    static func width(fromStoredWidth storedWidth: CGFloat, draggingBy translation: CGFloat, edge: String) -> CGFloat {
        let delta = edge == "left" ? translation : -translation
        return width(fromStoredWidth: storedWidth + delta)
    }

    static func frame(in visibleFrame: CGRect, edge: String, width: CGFloat) -> CGRect {
        let panelWidth = Self.width(fromStoredWidth: width)
        let x = edge == "left" ? visibleFrame.minX : visibleFrame.maxX - panelWidth
        return CGRect(x: x, y: visibleFrame.minY, width: panelWidth, height: visibleFrame.height)
    }
}

/// The panel is borderless, so it can never become the key window. Without
/// accepting the first mouse, a click that arrives while it is not frontmost
/// is swallowed by the activation attempt — which is why the close button only
/// sometimes fired on the first press.
private final class PanelHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
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

                    try feedRepository.update(feed, context: context)
                    let feedNewArticleCount = try await ArticleIngestProcessor().ingestParsed(
                        parsed.entries,
                        feedID: feed.id,
                        container: context.container
                    )
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
    @AppStorage("desktopPanelSmartCategories") private var selectedSmartCategoryIDs = ""
    @AppStorage("desktopPanelWidth") private var panelWidth = Double(DesktopPanelPlacement.defaultWidth)
    @AppStorage("desktopPanelEdge") private var panelEdge = "right"
    @AppStorage("desktopPanelBackground") private var backgroundHex = "#FFFFFF"
    @AppStorage("desktopPanelTextColor") private var textHex = "#000000"
    @AppStorage("desktopPanelOpacity") private var backgroundOpacity = 0.7
    @ObservedObject private var smartCategoryStore = SmartCategoryStore.shared
    @Environment(\.modelContext) private var modelContext

    let onClose: () -> Void
    let onResize: (CGFloat) -> Void

    /// Width the drag started at, so each change is measured from the original
    /// size instead of compounding against the width it just wrote.
    @State private var resizeBaseWidth: CGFloat?
    /// Live hover state of the resize strip — tells a drag's end whether the
    /// pointer is still on the strip, where the resize cursor belongs anyway.
    @State private var handleHovering = false

    private var visibleArticles: [ArticleRecord] {
        let availableFeedIDs = Set(articles.compactMap { $0.feed?.id })
        let selection = DesktopPanelFeedSelection.selectedFeedIDs(
            from: selectedFeedIDs,
            availableFeedIDs: availableFeedIDs
        )
        let smartCategoryIDs = Set(selectedSmartCategoryIDs.split(separator: ",").compactMap {
            UUID(uuidString: String($0))
        })
        let smartCategories = smartCategoryStore.categories.filter {
            smartCategoryIDs.contains($0.id) && !$0.isDeleted
        }
        let evaluator = SmartCategoryEvaluator()

        return Array(articles.lazy.filter { article in
            guard let feed = article.feed, !feed.muted else { return false }
            if selection.contains(feed.id) { return true }
            guard !smartCategories.isEmpty else { return false }
            let articleValue = Article(record: article)
            return smartCategories.contains { category in
                evaluator.matches(articleValue, category: category, feedName: feed.title, categoryName: feed.category?.name)
            }
        }.prefix(80))
    }

    private var panelBackground: Color {
        PrecisDesignSystem.color(hex: backgroundHex) ?? .white
    }

    /// Article title/summary ink — the Settings "Text color" swatch, falling
    /// back to the theme foreground until the user picks one.
    private var panelText: Color {
        PrecisDesignSystem.color(hex: textHex) ?? .black
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
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(PrecisDesignSystem.background(for: .light))
                        .frame(width: 26, height: 26)
                        // Solid chip drawn at full opacity: the header sits on
                        // `panelBackground.opacity(backgroundOpacity)`, so at low
                        // opacity the desktop shows through and a bare glyph
                        // loses its contrast. Ink-on-background is a fixed
                        // high-contrast pair in every theme and ignores both the
                        // panel colour and the transparency setting.
                        .background {
                            Circle()
                                .fill(PrecisDesignSystem.foreground(for: .light))
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide headlines")
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
                                openArticle(article)
                            } label: {
                                articleRow(article)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open \(article.title) from \(article.feed?.title ?? "feed") in browser")

                            Divider()
                                .overlay(PrecisDesignSystem.rule(for: .light))
                        }
                    }
                }
                .padding(.horizontal, PrecisSpacing.md)
            }
        }
        .frame(width: DesktopPanelPlacement.width(fromStoredWidth: CGFloat(panelWidth)))
        .background(panelBackground.opacity(backgroundOpacity))
        // The inner edge (the vertical side facing the screen) resizes the
        // panel by drag; the docked edge stays put.
        .overlay(alignment: panelEdge == "left" ? .trailing : .leading) {
            resizeHandle
        }
        .environment(\.colorScheme, PrecisTheme.current.colorScheme)
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let base = resizeBaseWidth
                            ?? DesktopPanelPlacement.width(fromStoredWidth: CGFloat(panelWidth))
                        if resizeBaseWidth == nil {
                            resizeBaseWidth = base
                        }
                        // Every step re-frames the panel, and AppKit re-runs
                        // its cursor pass on frame changes, which can drop the
                        // hover cursor mid-drag — pin it again each step.
                        NSCursor.resizeLeftRight.set()
                        onResize(
                            DesktopPanelPlacement.width(
                                fromStoredWidth: base,
                                draggingBy: value.translation.width,
                                edge: panelEdge
                            )
                        )
                    }
                    .onEnded { _ in
                        resizeBaseWidth = nil
                        // The last step pinned the resize cursor unconditionally —
                        // put the default back when the pointer is no longer on
                        // the strip (a hover exit can fire mid-drag).
                        if !handleHovering {
                            NSCursor.arrow.set()
                        }
                    }
            )
            .onHover { inside in
                handleHovering = inside
                if inside {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .help("Drag to resize")
    }

    private func openArticle(_ article: ArticleRecord) {
        // Reading happens in the browser, not in Precis — mark the row read
        // first so it greys out here and in the main window, then hand the
        // link to the system default browser.
        if !article.isRead {
            article.isRead = true
            do {
                try modelContext.save()
            } catch {
                PrecisLogger.error("Failed to mark panel article read: \(error.localizedDescription)")
            }
        }
        NotificationCenter.default.post(name: .precisArticleRead, object: article.id)
        guard let link = article.link, let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
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
                .foregroundStyle(article.isRead ? Color.gray : panelText)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(article.summary?.shortText ?? excerpt(for: article))
                .font(PrecisTypography.caption)
                .foregroundStyle(
                    article.isRead
                        ? Color.gray.opacity(0.75)
                        : panelText.opacity(0.72)
                )
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

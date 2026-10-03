import SwiftUI
import AppKit
import Combine
import SwiftData

struct MainWindowLayout: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: ArticleListViewModel
    @AppStorage("notifyOnNewArticles") private var notifyOnNewArticles = false
    @State private var selectedSidebarItem = "Unread"
    @State private var feedURLInput = ""
    @State private var isImporting = false
    @State private var isRefreshing = false
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
    @State private var isHoveringAddFeeds = false
    @State private var categories: [CategoryRecord] = []
    @State private var isAddingCategory = false
    @State private var newCategoryName = ""
    @State private var editingCategoryID: UUID?
    @State private var editingCategoryName = ""
    @State private var editingFeedID: UUID?
    @State private var editingFeedName = ""
    // Category whose color popover is open (set from its context menu).
    @State private var colorEditingCategoryID: UUID?
    @FocusState private var isCategoryInputFocused: Bool
    @FocusState private var isCategoryEditFocused: Bool
    @FocusState private var isFeedEditFocused: Bool
    @State private var categoryDropTargetID: UUID?
    @State private var categoryRowHeights: [UUID: CGFloat] = [:]
    @State private var articleListHeight: CGFloat = 350
    @State private var windowHeight: CGFloat = 900
    /// False at launch: the divider is parked halfway down the window on
    /// every layout pass until the user drags it themselves, so it opens
    /// dead-center no matter how the window reaches its size.
    @State private var userAdjustedDivider = false
    @State private var sidebarWidth: CGFloat = 260
    @State private var userAdjustedSidebarWidth = false
    @State private var isSidebarHidden = false
    /// Local keyDown monitor that maps the spacebar to "next article".
    /// Kept outside the view tree because `onKeyPress` on the focusable
    /// list never fires once focus lands on a child control (buttons,
    /// rows), which is why space appeared dead.
    @State private var spaceKeyMonitor: Any?
    /// Auto-hidden top chrome handling: when the menu bar reveals over a
    /// maximised/full-screen window it covers the top bar — and in full
    /// screen the titlebar comes down with it — so the content slides down by
    /// the revealed height while it's showing.
    @State private var hostingWindow: NSWindow?
    @State private var mouseMonitor: Any?
    @State private var globalMouseMonitor: Any?
    @State private var menuBarShift: CGFloat = 0
    @Environment(\.openWindow) private var openWindow
    private var selectedSummaryText: String? {
        guard let selectedItem = viewModel.selectedItem else { return nil }
        return viewModel.summaryText(for: selectedItem, context: modelContext)
    }

    private var digestFeedIDs: Set<UUID>? {
        switch viewModel.selectedSidebarFilter {
        case .category(let categoryID):
            return Set(viewModel.allFeeds.filter { $0.category?.id == categoryID }.map(\.id))
        case .feed(let feedID):
            return [feedID]
        default:
            return nil
        }
    }

    /// True when the current sidebar filter has no rows to show.
    private var listIsEmpty: Bool {
        viewModel.filteredItems.isEmpty
    }

    /// The pane shows this instead of a stale article whenever the list is
    /// empty — reuses the list's own wording so the two never disagree.
    private var paneEmptyMessage: String? {
        listIsEmpty ? viewModel.emptyStateTitle : nil
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
                            userAdjustedSidebarWidth = true
                            let newWidth = sidebarWidth + value.translation.width
                            sidebarWidth = max(180, min(newWidth, max(700, automaticSidebarWidth)))
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
                    onRevealSidebar: { isSidebarHidden = false },
                    headerTitle: selectedSidebarItem
                )
                .frame(height: articleListHeight)

                ResizableDivider()
                    .frame(height: 4)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                // First drag hands the position over to the
                                // user — launch centering no longer applies.
                                userAdjustedDivider = true
                                let newHeight = articleListHeight + value.translation.height
                                // Clamp against the window itself (not a fixed
                                // fraction of the screen) so the divider can be
                                // dragged to any position down to the last 140pt.
                                let maxHeight = max(150, windowHeight - 140)
                                articleListHeight = max(150, min(newHeight, maxHeight))
                            }
                    )

                ReadingPaneView(
                    item: listIsEmpty ? nil : viewModel.selectedItem,
                    emptyMessage: paneEmptyMessage,
                    summaryOverride: selectedSummaryText,
                    feedWideSummary: viewModel.feedWideSummaryText,
                    isGeneratingSummary: viewModel.isGeneratingFeedWideSummary,
                    summaryProgress: viewModel.feedWideSummaryProgress,
                    onOpenInBrowser: {
                        guard let link = viewModel.selectedItem?.link,
                              let url = URL(string: link) else { return }
                        NSWorkspace.shared.open(url)
                    },
                    isFetchingContent: !listIsEmpty && viewModel.loadingFullContentID == viewModel.selectedItem?.id,
                    onPreviousArticle: { viewModel.selectPrevious(context: modelContext) },
                    onNextArticle: { viewModel.selectNext(context: modelContext) },
                    canSelectPrevious: viewModel.canSelectPrevious,
                    canSelectNext: viewModel.canSelectNext
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
            if !userAdjustedDivider {
                // Not touched yet: open with the divider halfway down the
                // window (4pt is the divider itself). Re-applied on every
                // geometry event so intermediate window sizes during launch
                // can't leave it parked off-center.
                articleListHeight = max(150, (height - 4) / 2)
            } else {
                // The user owns the position now — if the window shrank below
                // the current list height, pull it back so the reading pane
                // never gets pushed off-screen.
                let cap = max(150, height - 140)
                if articleListHeight > cap {
                    articleListHeight = cap
                }
            }
        }
        .onChange(of: viewModel.selectedItemID) { _, _ in
            // A new story is being read — pull its full page (once per
            // article) so the pane shows the complete formatted article
            // instead of the feed's intro text.
            viewModel.loadFullContent(context: modelContext)
        }
        .onChange(of: viewModel.selectedFeedID) { _, _ in
            // Feed selection changed — regenerate digest for the new feed scope
            Task {
                await viewModel.generateFeedWideSummary(context: modelContext, feedIDs: digestFeedIDs)
            }
        }
        .onChange(of: viewModel.selectedSidebarFilter) { _, _ in
            Task {
                await viewModel.generateFeedWideSummary(context: modelContext, feedIDs: digestFeedIDs)
            }
        }
        .onAppear {
            DesktopFeedPanelController.shared.onOpenArticle = { articleID in
                if let readerWindow = NSApp.windows.first(where: {
                    $0.identifier?.rawValue == "PrecisMainWindow"
                }) {
                    NotificationCenter.default.post(name: .precisOpenArticle, object: articleID)
                    NSApp.activate(ignoringOtherApps: true)
                    if readerWindow.isMiniaturized {
                        readerWindow.deminiaturize(nil)
                    }
                    readerWindow.makeKeyAndOrderFront(nil)
                } else {
                    UserDefaults.standard.set(articleID.uuidString, forKey: "desktopPanelPendingArticleID")
                    openWindow(id: "main")
                }
            }
            refreshFeeds()
            refreshCategories()
            viewModel.loadFromContext(modelContext)
            if let pendingID = UserDefaults.standard.string(forKey: "desktopPanelPendingArticleID")
                .flatMap(UUID.init(uuidString:)) {
                UserDefaults.standard.removeObject(forKey: "desktopPanelPendingArticleID")
                openDesktopPanelArticle(pendingID)
            }
            // The launch selection needs its full content too — the
            // selection-change observer only fires for later clicks.
            viewModel.loadFullContent(context: modelContext)
            Task { await repairURLTitledFeeds() }
            viewModel.loadFolders(context: modelContext)
            startSpacebarMonitor()
            startMenuBarMonitor()
            // Auto-generate feed-wide 12-hour summary on launch
            Task {
                await viewModel.generateFeedWideSummary(context: modelContext, feedIDs: digestFeedIDs)
            }
        }
        .onDisappear {
            stopSpacebarMonitor()
            stopMenuBarMonitor()
        }
        .onReceive(NotificationCenter.default.publisher(for: .precisOpenSettings)) { _ in
            openWindow(id: "settings")
        }
        .onReceive(NotificationCenter.default.publisher(for: .precisOpenArticle)) { notification in
            guard let articleID = notification.object as? UUID else { return }
            openDesktopPanelArticle(articleID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .precisFeedsRefreshed)) { _ in
            refreshFeeds()
        }
        .onReceive(NotificationCenter.default.publisher(for: .precisFeedsImported)) { _ in
            // OPML import finished in the Settings window — reload the feed
            // list so the sidebar shows the new feeds immediately.
            refreshFeeds()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            updateMenuBarShift()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            updateMenuBarShift()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            updateMenuBarShift()
        }
        .background(
            WindowCaptureView { window in
                hostingWindow = window
                window?.identifier = NSUserInterfaceItemIdentifier("PrecisMainWindow")
                window?.acceptsMouseMovedEvents = true
                DispatchQueue.main.async { updateMenuBarShift() }
            }
        )
        // When the auto-hidden menu bar reveals over this window, drop the
        // content so the top bar sits below it (and below the full-screen
        // titlebar it brings with it) instead of underneath it.
        .padding(.top, menuBarShift)
        .background(PrecisDesignSystem.background(for: colorScheme))
    }

    // MARK: - Spacebar "next article"

    /// Listens for space globally and steps the selection down, so the
    /// shortcut works no matter what has keyboard focus. Three guards keep
    /// it out of the way: Command/Option combos (shortcuts), text editing
    /// (search field, inline rename fields → field editor is an NSText),
    /// and the article web view (WK* first responder keeps space as its
    /// native page-scroll). The press is swallowed so the list doesn't
    /// scroll as well.
    private func startSpacebarMonitor() {
        guard spaceKeyMonitor == nil else { return }
        let viewModel = self.viewModel
        let modelContext = self.modelContext
        spaceKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 49, // spacebar
                  !event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.option) else { return event }
            let responder = NSApp.keyWindow?.firstResponder
            if responder is NSText { return event }
            let className = responder.map { String(describing: Swift.type(of: $0)) } ?? ""
            if className.hasPrefix("WK") { return event }
            MainActor.assumeIsolated {
                viewModel.selectNext(context: modelContext)
            }
            return nil
        }
    }

    private func stopSpacebarMonitor() {
        if let spaceKeyMonitor {
            NSEvent.removeMonitor(spaceKeyMonitor)
            self.spaceKeyMonitor = nil
        }
    }

    // MARK: - Auto-hidden menu bar reveal

    /// Watches the mouse so `updateMenuBarShift()` can react whenever the
    /// pointer enters or leaves the menu bar strip. Both monitors are
    /// needed: while the menu bar overlays the window, its events can land
    /// on our app or elsewhere depending on focus.
    private func startMenuBarMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseUp]) { event in
            MainActor.assumeIsolated {
                updateMenuBarShift()
            }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseUp]) { _ in
            DispatchQueue.main.async {
                self.updateMenuBarShift()
            }
        }
    }

    private func stopMenuBarMonitor() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    /// Slides the window content down while the auto-hidden chrome is showing
    /// over a window that reaches the top of the screen (full screen, or
    /// maximised with the menu bar set to hide), and back up when it goes
    /// away. Clearing the menu bar alone is not enough in full screen: the
    /// window's titlebar — and the traffic-light buttons in it — comes down
    /// with the bar, right on top of the top row of the sidebar and list.
    private func updateMenuBarShift() {
        guard let window = hostingWindow,
              let screen = window.screen ?? NSScreen.main else { return }

        // Only windows that reach into the menu bar strip can be covered by
        // it — in windowed mode the menu bar never overlaps us, so shifting
        // would just add dead space.
        guard window.frame.maxY >= screen.frame.maxY - 1 else {
            if menuBarShift != 0 {
                withAnimation(.easeOut(duration: 0.15)) { menuBarShift = 0 }
            }
            return
        }

        let overlayHeight = menuBarOverlayHeight(on: screen)
        let mouse = NSEvent.mouseLocation
        let overMenuBar = overlayHeight > 0
            && mouse.x >= screen.frame.minX && mouse.x <= screen.frame.maxX
            && mouse.y >= screen.frame.maxY - overlayHeight
        // Keep the shift while the button is held so dragging a menu open
        // and down through the list doesn't yank the content mid-drag.
        let draggingThroughMenu = overlayHeight > 0 && menuBarShift > 0 && NSEvent.pressedMouseButtons != 0
        let target = TopChromeReveal.contentShift(
            isChromeRevealed: overMenuBar || draggingThroughMenu,
            menuBarHeight: overlayHeight,
            titlebarHeight: TopChromeReveal.revealedTitlebarHeight(for: window.styleMask)
        )
        guard target != menuBarShift else { return }
        withAnimation(.easeOut(duration: 0.2)) { menuBarShift = target }
    }

    /// Height the revealed menu bar actually occupies on this screen: the
    /// revealed bar is a top-edge window of the active app, so measure it
    /// when it's showing; otherwise fall back to the reserved strip.
    private func menuBarOverlayHeight(on screen: NSScreen) -> CGFloat {
        let top = screen.frame.maxY
        let measured = NSApp.windows
            .filter { candidate in
                guard candidate.isVisible,
                      candidate !== hostingWindow,
                      // Plain top-edge chrome: excludes menus/popovers
                      // (popup levels) and the main content windows.
                      candidate.level.rawValue < 100,
                      candidate.frame.height >= 20,
                      candidate.frame.height <= 64,
                      candidate.frame.maxY <= top + 2,
                      candidate.frame.maxY >= top - 64
                else { return false }
                return true
            }
            .map(\.frame.height)
            .max() ?? 0
        let reserved = top - screen.visibleFrame.maxY
        return max(measured, reserved)
    }

    private func refreshFeeds() {
        do {
            importedFeeds = try FeedRepository().fetchAll(context: modelContext)
            updateAutomaticSidebarWidth()
            viewModel.loadFolders(context: modelContext)
            viewModel.loadArticles(for: viewModel.selectedFeedID, context: modelContext)
            // Regenerate feed-wide summary after refresh
            Task {
                await viewModel.generateFeedWideSummary(context: modelContext, feedIDs: digestFeedIDs)
            }
        } catch {
            importedFeeds = []
            updateAutomaticSidebarWidth()
        }
    }

    private func openDesktopPanelArticle(_ articleID: UUID) {
        if !viewModel.items.contains(where: { $0.id == articleID }) {
            viewModel.loadArticles(for: nil, context: modelContext)
        }
        guard let item = viewModel.items.first(where: { $0.id == articleID }) else { return }
        viewModel.select(item, context: modelContext)
        viewModel.loadFullContent(context: modelContext)
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

    // MARK: - Category color

    /// Live binding from the color popover into the category's persisted
    /// tint — every picker change writes and saves so the sidebar row
    /// re-renders as the user drags.
    private func categoryColorBinding(for category: CategoryRecord) -> Binding<Color> {
        Binding(
            get: {
                category.colorHex.flatMap { PrecisDesignSystem.color(hex: $0) } ?? Color.accentColor
            },
            set: { newColor in
                category.colorHex = PrecisDesignSystem.hexString(from: newColor)
                saveCategoryTint()
            }
        )
    }

    private func saveCategoryTint() {
        do {
            try modelContext.save()
        } catch {
            PrecisLogger.error("Failed to save category color: \(error.localizedDescription)")
        }
    }

    /// Color picker popover for a category's text and icon tint.
    private func categoryColorPopover(for category: CategoryRecord) -> some View {
        VStack(alignment: .leading, spacing: PrecisSpacing.sm) {
            Text("Text & Icon Color")
                .font(PrecisTypography.metadata)
                .foregroundStyle(PrecisDesignSystem.marginalia)
                .textCase(.uppercase)
                .tracking(1.2)

            ColorPicker(
                "Color",
                selection: categoryColorBinding(for: category),
                supportsOpacity: false
            )

            HStack {
                Button("Use Default") {
                    category.colorHex = nil
                    saveCategoryTint()
                }
                .disabled(category.colorHex == nil)

                Spacer()

                Button("Done") {
                    colorEditingCategoryID = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(PrecisSpacing.md)
        .frame(minWidth: 260)
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
                updateAutomaticSidebarWidth()
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

    private func beginEditingFeed(_ feed: FeedRecord) {
        editingFeedID = feed.id
        editingFeedName = feed.sidebarTitle ?? FeedDiscoveryService.conciseTitle(feed.title)
        DispatchQueue.main.async {
            isFeedEditFocused = true
        }
    }

    private func commitFeedRename(_ feed: FeedRecord) {
        guard editingFeedID == feed.id else { return }
        let name = editingFeedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            feed.sidebarTitle = name
            do {
                try modelContext.save()
            } catch {
                PrecisLogger.error("Failed to rename feed: \(error.localizedDescription)")
            }
        }
        editingFeedID = nil
        isFeedEditFocused = false
    }

    private func cancelFeedRename() {
        editingFeedID = nil
        editingFeedName = ""
        isFeedEditFocused = false
    }

    private func sidebarDisplayTitle(for feed: FeedRecord) -> String {
        if let sidebarTitle = feed.sidebarTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !sidebarTitle.isEmpty {
            return sidebarTitle
        }
        return FeedDiscoveryService.conciseTitle(feed.title)
    }

    private var automaticSidebarWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: 15, weight: .regular)
        let widestFeedName = importedFeeds
            .map { ceil((sidebarDisplayTitle(for: $0) as NSString).size(withAttributes: [.font: font]).width) }
            .max() ?? 0
        // Slack covers checkbox + favicon + title→badge spacing + unread
        // capsule + row insets. The last-fetched time is gone, so this
        // dropped from 180 — names and badges still fit on one line.
        return max(260, widestFeedName + 130)
    }

    private func updateAutomaticSidebarWidth() {
        guard !userAdjustedSidebarWidth else { return }
        sidebarWidth = automaticSidebarWidth
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
        // Match the drag/bulk paths — reload + regenerate the digest so the
        // moved feed's scope shows a fresh Precis instead of a stale one.
        refreshFeeds()
    }

    /// Moves every checked feed in one save, then clears the selection so
    /// the action bar retires — the move is visibly "done".
    private func moveCheckedFeeds(to category: CategoryRecord?) {
        let checked = importedFeeds.filter { selectedFeedIDs.contains($0.id) }
        for feed in checked where feed.category?.id != category?.id {
            feed.category = category
        }
        do {
            try modelContext.save()
        } catch {
            PrecisLogger.error("Failed to move feeds to category: \(error.localizedDescription)")
        }
        selectedFeedIDs.removeAll()
        selectionAnchorID = nil
        refreshFeeds()
    }

    // MARK: - Drag-to-category

    /// Prefix marks a drag payload as a feed multi-selection rather than a
    /// category reorder (both travel as plain `String`s).
    private static let feedDragPrefix = "precis-feeds:"

    /// Dragging a checked row carries the whole selection; dragging an
    /// unchecked row carries just that feed — either way it can be dropped
    /// on a category header.
    private func feedDragPayload(_ feed: FeedRecord) -> String {
        let ids = selectedFeedIDs.contains(feed.id) ? Array(selectedFeedIDs) : [feed.id]
        return Self.feedDragPrefix + ids.map(\.uuidString).joined(separator: ",")
    }

    private func moveFeeds(ids: [UUID], to category: CategoryRecord?) {
        let moved = importedFeeds.filter { ids.contains($0.id) }
        for feed in moved where feed.category?.id != category?.id {
            feed.category = category
        }
        do {
            try modelContext.save()
        } catch {
            PrecisLogger.error("Failed to drop feeds into category: \(error.localizedDescription)")
        }
        refreshFeeds()
    }

    /// True when this row is part of a multi-selection — the context menu's
    /// Move item then targets every checked feed, not just the row clicked.
    private func movesWholeSelection(_ feed: FeedRecord) -> Bool {
        selectedFeedIDs.count >= 2 && selectedFeedIDs.contains(feed.id)
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
        selectedSidebarItem = sidebarDisplayTitle(for: feed)
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

            if editingFeedID == feed.id {
                TextField("Feed name", text: $editingFeedName)
                    .textFieldStyle(.roundedBorder)
                    .font(PrecisTypography.body)
                    .focused($isFeedEditFocused)
                    .onSubmit { commitFeedRename(feed) }
                    .onExitCommand { cancelFeedRename() }
                    .onChange(of: isFeedEditFocused) { _, focused in
                        if !focused && editingFeedID == feed.id {
                            commitFeedRename(feed)
                        }
                    }
            } else {
                Button(action: {
                    handleFeedClick(feed, group: group)
                }) {
                    HStack(spacing: 8) {
                        FeedFaviconView(url: feed.url)
                            .frame(width: 16, height: 16)
                        Text(sidebarDisplayTitle(for: feed))
                            .font(PrecisTypography.body)
                            .lineLimit(1)
                            .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.8))
                    }
                }
                .buttonStyle(.plain)
            }

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

            // Per-row last-fetched time ("1h ago") removed — the trailing
            // slack in `automaticSidebarWidth` shrank to match.
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
                Task { _ = await refreshSingleFeed(feed) }
            } label: {
                Label("Refresh Feed", systemImage: "arrow.clockwise")
            }
            Button {
                beginEditingFeed(feed)
            } label: {
                Label("Rename Feed…", systemImage: "pencil")
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
                // Right-clicking a checked row moves the whole selection —
                // same payload as the drag gesture; single rows behave as
                // before.
                Button {
                    if movesWholeSelection(feed) { moveCheckedFeeds(to: nil) } else { moveFeed(feed, to: nil) }
                } label: {
                    Label("No Category", systemImage: !movesWholeSelection(feed) && feed.category == nil ? "checkmark" : "square")
                }
                Divider()
                if categories.isEmpty {
                    Text("No categories yet")
                } else {
                    ForEach(categories) { category in
                        Button {
                            if movesWholeSelection(feed) { moveCheckedFeeds(to: category) } else { moveFeed(feed, to: category) }
                        } label: {
                            Label(category.name, systemImage: !movesWholeSelection(feed) && feed.category?.id == category.id ? "checkmark" : "square")
                        }
                    }
                }
            } label: {
                Label(movesWholeSelection(feed) ? "Move \(selectedFeedIDs.count) Feeds to Category" : "Move to Category", systemImage: "folder")
            }
        }
        .onAppear {
            // Diagnostic trail: a category-nested row logging
            // indent=0/compact=false means the stale-row bug is back.
            PrecisLogger.info("Row appeared: \(feed.title) indent=\(indent) compact=\(compact)")
        }
        // Drag the row onto a category header to move it (or the whole
        // checked selection, if this row is part of one). Visual payload is
        // a simple label — the ID list rides in the payload string.
        .draggable(feedDragPayload(feed)) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up")
                    .foregroundStyle(Color.accentColor)
                Text(selectedFeedIDs.contains(feed.id) && selectedFeedIDs.count > 1
                     ? "\(selectedFeedIDs.count) feeds"
                     : sidebarDisplayTitle(for: feed))
                    .font(PrecisTypography.body)
                    .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    /// `reload: false` skips the full UI/library reload — refresh-all passes
    /// it for every feed and reloads ONCE at the end. Reloading per feed made
    /// a 400-feed pass rebuild the whole article library 400 times on the
    /// main thread (sampled: the main thread spent most of its time there).
    private func refreshSingleFeed(_ feed: FeedRecord, reload: Bool = true, sendNotification: Bool = true) async -> Int {
        importStatus = "Refreshing \(feed.title)…"
        importStatusKind = .neutral

        do {
            let feedURL = URL(string: feed.url) ?? URL(string: "https://example.com/feed.xml")!
            let parsed = try await FeedRefreshService().fetchAndParse(Feed(title: feed.title, url: feedURL))
            var newArticleCount = 0

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
                    contentHTML: entry.contentHTML,
                    isRead: false,
                    isStarred: false,
                    imageURL: entry.imageURL?.absoluteString
                )
                if try ArticleRepository().saveIfNew(article, context: modelContext) {
                    newArticleCount += 1
                }
            }

            try FeedRepository().update(feed, context: modelContext)
            if reload {
                refreshFeeds()
            }
            if sendNotification, notifyOnNewArticles, newArticleCount > 0 {
                try? await NewArticleNotificationService.sendNewArticlesNotification(
                    count: newArticleCount,
                    feedNames: [sidebarDisplayTitle(for: feed)]
                )
            }
            importStatus = "\(feed.title) refreshed"
            importStatusKind = .success
            return newArticleCount
        } catch {
            importStatus = "Refresh failed: \(error.localizedDescription)"
            importStatusKind = .error
            return 0
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
        guard AppScopedFeedRefreshCoordinator.shared.beginManualRefresh() else { return }
        isRefreshingAll = true
        defer {
            isRefreshingAll = false
            AppScopedFeedRefreshCoordinator.shared.endManualRefresh()
        }
        var totalNewArticles = 0
        var refreshedFeedNames: [String] = []
        for feed in importedFeeds {
            // No per-feed UI reload — reload once after the whole pass.
            let newArticleCount = await refreshSingleFeed(feed, reload: false, sendNotification: false)
            if newArticleCount > 0 {
                totalNewArticles += newArticleCount
                refreshedFeedNames.append(sidebarDisplayTitle(for: feed))
            }
        }
        refreshFeeds()
        if notifyOnNewArticles, totalNewArticles > 0 {
            try? await NewArticleNotificationService.sendNewArticlesNotification(
                count: totalNewArticles,
                feedNames: refreshedFeedNames
            )
        }
        importStatus = "All feeds refreshed"
        importStatusKind = .success
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
                    var seenFeedURLs = Set(
                        try feedRepository.fetchAll(context: modelContext)
                            .map { FeedRepository.canonicalURLString($0.url) }
                    )
                    var importedCount = 0

                    var folderCache: [String: FolderRecord] = [:]

                    for opmlFeed in opmlFeeds {
                        let inputURL = FeedRepository.canonicalURLString(opmlFeed.url)
                        guard seenFeedURLs.insert(inputURL).inserted else { continue }
                        let resolvedURL: URL?
                        if let url = URL(string: opmlFeed.url), url.host != nil {
                            resolvedURL = await FeedDiscoveryService.resolveFeedURL(url)
                        } else {
                            resolvedURL = nil
                        }
                        let storedURL = resolvedURL?.absoluteString ?? opmlFeed.url
                        let storedURLKey = FeedRepository.canonicalURLString(storedURL)
                        if storedURLKey != inputURL && !seenFeedURLs.insert(storedURLKey).inserted {
                            continue
                        }

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
                            url: storedURL,
                            folder: folderRecord,
                            context: modelContext
                        )
                        importedCount += 1

                        // Fetch articles for each feed
                        if let feedURL = resolvedURL ?? URL(string: storedURL) {
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
                                        contentHTML: entry.contentHTML,
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
                    let skippedCount = opmlFeeds.count - importedCount
                    importStatus = skippedCount > 0
                        ? "Imported \(importedCount) feeds; \(skippedCount) already subscribed"
                        : "Imported \(importedCount) feeds from OPML"
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
                    HStack(spacing: 5) {
                        Text("Add Feeds")
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Image(systemName: "plus.circle")
                            .font(.title3)
                    }
                    // macOS accent color on the label + icon, sitting on the
                    // same faint accent wash as the add-category + chip.
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(isHoveringAddFeeds ? 0.24 : 0.12))
                    )
                }
                .buttonStyle(.plain)
                .onHover { isHoveringAddFeeds = $0 }
                .animation(.easeOut(duration: 0.15), value: isHoveringAddFeeds)
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
                        // User-chosen tint from "Change Color…" — nil keeps
                        // the default selection/neutral row colors.
                        let customTint = category.colorHex.flatMap { PrecisDesignSystem.color(hex: $0) }
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
                                .foregroundStyle(customTint ?? (isCategorySelected ? Color.accentColor : PrecisDesignSystem.foreground(for: colorScheme).opacity(0.6)))

                            Text(category.name)
                                .font(PrecisTypography.body)
                                .fontWeight(isCategorySelected ? .semibold : nil)
                                .foregroundStyle(customTint ?? (isCategorySelected ? Color.accentColor : PrecisDesignSystem.foreground(for: colorScheme).opacity(0.75)))

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
                            guard let first = items.first else { return false }

                            // Feed payload: drop checked rows (or a single
                            // dragged feed) into this category.
                            if first.hasPrefix(Self.feedDragPrefix) {
                                let ids = first
                                    .dropFirst(Self.feedDragPrefix.count)
                                    .split(separator: ",")
                                    .compactMap { UUID(uuidString: String($0)) }
                                guard !ids.isEmpty else { return false }
                                categoryDropTargetID = nil
                                PrecisLogger.info("Feed drop → category: \(ids.count) feed(s)")
                                moveFeeds(ids: ids, to: category)
                                return true
                            }

                            guard let sourceID = UUID(uuidString: first),
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
                            Button {
                                colorEditingCategoryID = category.id
                            } label: {
                                Label("Change Color…", systemImage: "paintpalette")
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
                        .popover(isPresented: Binding(
                            get: { colorEditingCategoryID == category.id },
                            set: { presented in
                                // Only clear when THIS row's popover dismissed —
                                // switching to another category must not race it.
                                if !presented, colorEditingCategoryID == category.id {
                                    colorEditingCategoryID = nil
                                }
                            }
                        )) {
                            categoryColorPopover(for: category)
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
                    Spacer()

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
                onAdd: { feedURL in
                    Task {
                        isImporting = true
                        importStatus = ""
                        importStatusKind = .neutral
                        do {
                            let before = (try? ArticleRepository().fetchAll(context: modelContext).count) ?? 0
                            try await viewModel.importFeed(from: feedURL, in: modelContext)
                            refreshFeeds()
                            viewModel.selectedSidebarFilter = .all
                            selectedSidebarItem = "All Items"
                            viewModel.loadArticles(for: nil, context: modelContext)
                            let after = (try? ArticleRepository().fetchAll(context: modelContext).count) ?? 0
                            let added = max(0, after - before)
                            // Stay open so several feeds can be added back-to-
                            // back; "Done" (or the ✕) closes the sheet.
                            importStatus = added > 0
                                ? "Added \(added) new article\(added == 1 ? "" : "s") — add another feed to continue"
                                : "Feed added — no new articles yet; add another feed to continue"
                            importStatusKind = .success
                            feedURLInput = ""
                        } catch FeedRepositoryError.duplicateFeed(let existingTitle) {
                            importStatus = "Already subscribed as \"\(existingTitle)\""
                            importStatusKind = .neutral
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
    let onAdd: (String) -> Void
    @State private var didImport = false
    @State private var selectedFeedURL = ""
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

            Text("Or add a feed manually")
                .font(PrecisTypography.metadata.weight(.medium))
                .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))

            TextField("", text: $feedURLInput, prompt: isURLEntryFocused
                ? nil
                : Text("https://example.com/feed.xml or any supported URL"))
                .textFieldStyle(.roundedBorder)
                .font(PrecisTypography.body)
                .focused($isURLEntryFocused)
                .onSubmit { onAdd(feedURLInput) }

            HStack(spacing: 12) {
                Button(action: { onAdd(feedURLInput) }) {
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

            Divider()

            VStack(alignment: .leading, spacing: PrecisSpacing.xs) {
                Text("SUGGESTED FEEDS")
                    .font(PrecisTypography.caption)
                    .foregroundStyle(PrecisDesignSystem.marginalia)

                Picker("", selection: $selectedFeedURL) {
                    Text("Browse by category...").tag("")
                    ForEach(SuggestedFeedCatalog.categories) { category in
                        Section(category.name) {
                            ForEach(category.feeds) { feed in
                                Text(feed.name).tag(feed.url)
                            }
                        }
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: selectedFeedURL) { _, url in
                    guard !url.isEmpty else { return }
                    feedURLInput = url
                    importStatus = ""
                    importStatusKind = .neutral
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
        .frame(width: 460)
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

private struct SuggestedFeed: Identifiable {
    let name: String
    let url: String

    var id: String { url }
}

private struct SuggestedFeedCategory: Identifiable {
    let name: String
    let feeds: [SuggestedFeed]

    var id: String { name }
}

private enum SuggestedFeedCatalog {
    static let categories = [
        SuggestedFeedCategory(name: "News", feeds: [
            SuggestedFeed(name: "BBC World News", url: "https://feeds.bbci.co.uk/news/world/rss.xml"),
            SuggestedFeed(name: "The Guardian: World", url: "https://www.theguardian.com/world/rss"),
            SuggestedFeed(name: "NPR News", url: "https://feeds.npr.org/1001/rss.xml"),
            SuggestedFeed(name: "CNN: World", url: "http://rss.cnn.com/rss/edition_world.rss"),
            SuggestedFeed(name: "The New York Times: Top Stories", url: "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml"),
            SuggestedFeed(name: "Sky News: World", url: "https://feeds.skynews.com/feeds/rss/world.xml"),
            SuggestedFeed(name: "Google News", url: "https://news.google.com/rss")
        ]),
        SuggestedFeedCategory(name: "Sports", feeds: [
            SuggestedFeed(name: "BBC Sport", url: "https://feeds.bbci.co.uk/sport/rss.xml"),
            SuggestedFeed(name: "ESPN Top Headlines", url: "https://www.espn.com/espn/rss/news"),
            SuggestedFeed(name: "BBC Football", url: "https://feeds.bbci.co.uk/sport/football/rss.xml"),
            SuggestedFeed(name: "Sky Sports: Football", url: "https://www.skysports.com/rss/12040"),
            SuggestedFeed(name: "ESPN: Soccer", url: "https://www.espn.com/espn/rss/soccer/news"),
            SuggestedFeed(name: "ESPN: NBA", url: "https://www.espn.com/espn/rss/nba/news"),
            SuggestedFeed(name: "ESPN: NFL", url: "https://www.espn.com/espn/rss/nfl/news")
        ]),
        SuggestedFeedCategory(name: "Technology", feeds: [
            SuggestedFeed(name: "Ars Technica", url: "https://feeds.arstechnica.com/arstechnica/index"),
            SuggestedFeed(name: "The Verge", url: "https://www.theverge.com/rss/index.xml"),
            SuggestedFeed(name: "Hacker News", url: "https://news.ycombinator.com/rss"),
            SuggestedFeed(name: "TechCrunch", url: "https://techcrunch.com/feed/"),
            SuggestedFeed(name: "WIRED", url: "https://www.wired.com/feed/rss"),
            SuggestedFeed(name: "Engadget", url: "https://www.engadget.com/rss.xml"),
            SuggestedFeed(name: "CNET News", url: "https://www.cnet.com/rss/news/")
        ]),
        SuggestedFeedCategory(name: "AI", feeds: [
            SuggestedFeed(name: "The Decoder", url: "https://the-decoder.com/feed/"),
            SuggestedFeed(name: "Hugging Face Blog", url: "https://huggingface.co/blog/feed.xml"),
            SuggestedFeed(name: "MIT Technology Review: AI", url: "https://www.technologyreview.com/topic/artificial-intelligence/feed/"),
            SuggestedFeed(name: "MarkTechPost", url: "https://www.marktechpost.com/feed/"),
            SuggestedFeed(name: "Import AI", url: "https://importai.substack.com/feed"),
            SuggestedFeed(name: "Latent Space", url: "https://www.latent.space/feed"),
            SuggestedFeed(name: "Google Research Blog", url: "https://blog.research.google/feeds/posts/default?alt=rss")
        ]),
        SuggestedFeedCategory(name: "Business", feeds: [
            SuggestedFeed(name: "Axios", url: "https://api.axios.com/feed/"),
            SuggestedFeed(name: "Financial Times", url: "https://www.ft.com/?format=rss"),
            SuggestedFeed(name: "Bloomberg Markets", url: "https://feeds.bloomberg.com/markets/news.rss"),
            SuggestedFeed(name: "MarketWatch: Top Stories", url: "https://www.marketwatch.com/rss/topstories"),
            SuggestedFeed(name: "Business Insider", url: "https://www.businessinsider.com/rss"),
            SuggestedFeed(name: "The Economist: Business", url: "https://www.economist.com/business/rss.xml")
        ]),
        SuggestedFeedCategory(name: "Science", feeds: [
            SuggestedFeed(name: "Nature", url: "https://www.nature.com/nature.rss"),
            SuggestedFeed(name: "ScienceDaily", url: "https://www.sciencedaily.com/rss/all.xml"),
            SuggestedFeed(name: "ScienceAlert", url: "https://www.sciencealert.com/feed"),
            SuggestedFeed(name: "NASA Breaking News", url: "https://www.nasa.gov/rss/dyn/breaking_news.rss"),
            SuggestedFeed(name: "Scientific American", url: "http://rss.sciam.com/ScientificAmerican-Global"),
            SuggestedFeed(name: "Space.com", url: "https://www.space.com/feeds/all"),
            SuggestedFeed(name: "New Scientist", url: "https://www.newscientist.com/feed/"),
            SuggestedFeed(name: "Science News", url: "https://www.sciencenews.org/feed"),
            SuggestedFeed(name: "Quanta Magazine", url: "https://www.quantamagazine.org/feed/"),
            SuggestedFeed(name: "BBC Science & Environment", url: "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml")
        ]),
        SuggestedFeedCategory(name: "Movies", feeds: [
            SuggestedFeed(name: "Variety: Film", url: "https://variety.com/feed/"),
            SuggestedFeed(name: "Deadline", url: "https://deadline.com/feed/"),
            SuggestedFeed(name: "IndieWire", url: "https://www.indiewire.com/feed/"),
            SuggestedFeed(name: "Slashfilm", url: "https://www.slashfilm.com/feed/"),
            SuggestedFeed(name: "ComingSoon", url: "https://www.comingsoon.net/feed")
        ]),
        SuggestedFeedCategory(name: "Music", feeds: [
            SuggestedFeed(name: "Pitchfork: News", url: "https://pitchfork.com/feed/feed-news/rss"),
            SuggestedFeed(name: "Consequence", url: "https://consequence.net/feed/"),
            SuggestedFeed(name: "Stereogum", url: "https://stereogum.com/feed"),
            SuggestedFeed(name: "NPR Music", url: "https://feeds.npr.org/1039/rss.xml"),
            SuggestedFeed(name: "Music Business Worldwide", url: "https://www.musicbusinessworldwide.com/feed/"),
            SuggestedFeed(name: "The Guardian: Music", url: "https://www.theguardian.com/music/rss")
        ]),
        SuggestedFeedCategory(name: "Photography", feeds: [
            SuggestedFeed(name: "PetaPixel", url: "https://petapixel.com/feed/"),
            SuggestedFeed(name: "Fstoppers", url: "https://fstoppers.com/feed"),
            SuggestedFeed(name: "DIY Photography", url: "https://www.diyphotography.net/feed/"),
            SuggestedFeed(name: "Digital Photography School", url: "https://digital-photography-school.com/feed/"),
            SuggestedFeed(name: "Canon Rumors", url: "https://www.canonrumors.com/feed/"),
            SuggestedFeed(name: "DPReview", url: "https://www.dpreview.com/feed/")
        ]),
        SuggestedFeedCategory(name: "Gaming", feeds: [
            SuggestedFeed(name: "Polygon", url: "https://www.polygon.com/rss/index.xml"),
            SuggestedFeed(name: "GameSpot", url: "https://www.gamespot.com/feeds/mashup/"),
            SuggestedFeed(name: "PC Gamer", url: "https://www.pcgamer.com/rss/"),
            SuggestedFeed(name: "Rock Paper Shotgun", url: "https://www.rockpapershotgun.com/feed"),
            SuggestedFeed(name: "Eurogamer", url: "https://www.eurogamer.net/?format=rss"),
            SuggestedFeed(name: "Steam News", url: "https://store.steampowered.com/feeds/news.xml")
        ]),
        SuggestedFeedCategory(name: "Apple", feeds: [
            SuggestedFeed(name: "9to5Mac", url: "https://9to5mac.com/feed/"),
            SuggestedFeed(name: "Apple Newsroom", url: "https://www.apple.com/newsroom/rss-feed.rss"),
            SuggestedFeed(name: "AppleInsider", url: "https://appleinsider.com/rss/news/"),
            SuggestedFeed(name: "MacRumors", url: "https://feeds.macrumors.com/MacRumors-All"),
            SuggestedFeed(name: "MacStories", url: "https://www.macstories.net/feed/"),
            SuggestedFeed(name: "Daring Fireball", url: "https://daringfireball.net/feeds/main")
        ])
    ]

    static func category(named name: String) -> SuggestedFeedCategory? {
        categories.first { $0.name == name }
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Soft tile: favicons are often white-on-transparent (built for
            // dark toolbars) and would vanish against a light sidebar
            // without something behind them.
            RoundedRectangle(cornerRadius: 4)
                .fill(PrecisDesignSystem.marginalia.opacity(0.12))

            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Shown while fetching, and kept as the permanent fallback
                // when a host serves nothing usable. The old "rss" symbol
                // doesn't exist on macOS and rendered an empty box.
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(PrecisDesignSystem.marginalia)
            }
        }
        .frame(width: 16, height: 16)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(PrecisDesignSystem.rule(for: colorScheme), lineWidth: 0.5)
        )
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

// MARK: - Window Capture

/// Zero-size view that reports the hosting window so the layout can compare
/// its frame against the screen (menu bar reveal detection).
private struct WindowCaptureView: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void

    final class Coordinator {
        var window: NSWindow?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { report(view.window, context: context) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { report(nsView.window, context: context) }
    }

    private func report(_ window: NSWindow?, context: Context) {
        guard context.coordinator.window !== window else { return }
        context.coordinator.window = window
        onWindow(window)
    }
}

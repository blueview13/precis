import SwiftUI
import ImageIO
import SwiftData

struct ArticleListView: View {
    @ObservedObject var viewModel: ArticleListViewModel
    /// Set by the shell so the sidebar can be revealed again from the list
    /// header while the sidebar itself is hidden.
    var isSidebarHidden: Bool = false
    var onRevealSidebar: (() -> Void)? = nil
    /// Header title — mirrors the sidebar's current selection (a feed or
    /// category name, or All Items / Unread / Starred).
    var headerTitle: String = "Unread"
    /// True while the reading pane sits beside the headlines (three-column
    /// layout) — drives the header toggle's icon and help text.
    var isColumnLayout: Bool = false
    /// Flips between the stacked and three-column reading layouts.
    var onToggleLayout: (() -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("showThumbnails") private var showThumbnails: Bool = true
    @FocusState private var isSearchFieldFocused: Bool
    // Backup invalidation: the view model also observes this key directly and
    // republishes `sortPreference`, so the list re-sorts the moment Settings
    // changes it.
    @AppStorage("defaultSortOrder") private var defaultSortOrder: String = "newest"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if isSidebarHidden {
                    Button(action: { onRevealSidebar?() }) {
                        Image(systemName: "sidebar.left")
                            .font(.title3)
                            .foregroundStyle(PrecisDesignSystem.marginalia)
                    }
                    .buttonStyle(.plain)
                    .help("Show sidebar")
                }

                // Reading-layout toggle, kept at the LEADING edge of the
                // header so it sits in the same spot in both layouts (it used
                // to jump to the far right of a wider column, which meant
                // hunting for it when switching). The icon shows the layout a
                // click switches TO.
                Button(action: { onToggleLayout?() }) {
                    Image(systemName: isColumnLayout ? "rectangle.split.1x2" : "rectangle.split.3x1")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(PrecisDesignSystem.marginalia)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isColumnLayout ? "Stack headlines above article" : "Show headlines beside article")
                .help(isColumnLayout ? "Stacked layout — headlines above the article" : "Three-column layout — headlines beside the article")

                Text(headerTitle)
                    .font(PrecisTypography.headline)
                    .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))
                    .lineLimit(1)

                Spacer()

                // Bulk read-state actions on the visible list. Kept INBOARD of
                // the search field rather than flush against the column's
                // trailing edge: at the narrow column widths the header used
                // to overflow and park the envelope icon right on the column
                // crease, where the resize divider made it awkward to click.
                if viewModel.visibleHasUnread {
                    Button(action: {
                        let visibleArticleIDs = Set(viewModel.filteredItems.map(\.id))
                        viewModel.markAllAsRead(context: modelContext, articleIDs: visibleArticleIDs)
                    }) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(PrecisDesignSystem.marginalia)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                            .help("Mark visible articles as read")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mark visible articles as read")
                    .help("Mark visible articles as read")
                }

                if viewModel.visibleHasRead {
                    Button(action: {
                        let visibleArticleIDs = Set(viewModel.filteredItems.map(\.id))
                        viewModel.markAllAsUnread(context: modelContext, articleIDs: visibleArticleIDs)
                    }) {
                        Image(systemName: "envelope.badge")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(PrecisDesignSystem.marginalia)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                            .help("Mark visible articles as unread")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mark visible articles as unread")
                    .help("Mark visible articles as unread")
                }

                // Shares the article open in the reading pane via the
                // system share menu (Mail, Messages, Copy Link, …).
                if let item = viewModel.selectedItem,
                   let link = item.link,
                   let url = URL(string: link) {
                    ShareLink(
                        item: url,
                        subject: Text(item.title),
                        message: Text(item.title)
                    ) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(PrecisDesignSystem.marginalia)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share article")
                    .help("Share article")
                }

                // Compact search — sits in the header bar rather than as a
                // full-width row of its own above the list. Its width is
                // flexible so a narrow column shrinks the field instead of
                // overflowing and shoving the icons past the column edge.
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(PrecisDesignSystem.marginalia)
                        .font(.caption)

                    TextField("Search articles...", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .font(PrecisTypography.body)
                        .focused($isSearchFieldFocused)

                    // One-click clear — otherwise the query has to be deleted
                    // by hand. Hidden while the field is empty.
                    if !viewModel.searchText.isEmpty {
                        Button {
                            viewModel.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(PrecisDesignSystem.marginalia.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                        .help("Clear search")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(PrecisDesignSystem.rule(for: colorScheme), lineWidth: 1)
                )
                .frame(minWidth: 110, maxWidth: 228)
            }
            .padding(PrecisSpacing.md)

            ScrollViewReader { proxy in
                ScrollView {
                    if viewModel.filteredItems.isEmpty {
                        // No more blank pane — explain why the list is empty
                        // (e.g. Unread filter right after "Mark All Read").
                        VStack(spacing: PrecisSpacing.xs) {
                            Image(systemName: "checkmark.circle")
                                .font(.title2)
                                .foregroundStyle(PrecisDesignSystem.marginalia.opacity(0.6))

                            Text(viewModel.emptyStateTitle)
                                .font(PrecisTypography.body)
                                .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.6))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 64)
                        .padding(.horizontal, PrecisSpacing.md)
                    } else {
                        // Lazy: a full-window layout pass (first context-menu open
                        // triggers one) must only measure visible rows — the eager
                        // VStack measured every article and stalled the main thread.
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(viewModel.filteredItems) { item in
                                ArticleListRow(
                                    item: item,
                                    isSelected: viewModel.selectedItemID == item.id,
                                    showThumbnails: showThumbnails,
                                    onSelect: { viewModel.select(item, context: modelContext) },
                                    onToggleStar: { viewModel.toggleStarred(item, context: modelContext) },
                                    showsThumbnailAbove: isColumnLayout
                                )
                                .contentShape(Rectangle())
                                .id(item.id)
                            }
                        }
                    }
                }
                // Rebuild the scroll view when the sidebar filter changes so the
                // new list opens at its top — a preserved offset landed on an
                // arbitrary mid-list article instead.
                .id(viewModel.selectedSidebarFilter)
                // ‹ › (and the arrow keys) stepped the selection — glide the
                // list so the selected row stays in view, one step at a time.
                .onChange(of: viewModel.listScrollRevealToken) { _, _ in
                    guard let selectedID = viewModel.selectedItemID else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(selectedID, anchor: .center)
                    }
                }
            }
        }
        .background(PrecisDesignSystem.background(for: colorScheme))
        .focusable()
        // Suppress the system-accent focus ring — with a green macOS accent it
        // painted green borders along the list's left/bottom edges. Keyboard
        // nav (arrows/d/s) still works; selection shows via the row flag bar.
        .focusEffectDisabled(true)
        .onKeyPress(.upArrow) {
            guard !isSearchFieldFocused else { return .ignored }
            viewModel.selectPrevious(context: modelContext)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !isSearchFieldFocused else { return .ignored }
            viewModel.selectNext(context: modelContext)
            return .handled
        }
        // Spacebar steps down the list (any feed/category scope) — an
        // easy target alongside the arrow keys. Ignored while typing in
        // search. (`<`/`>` were tried first but the shifted key codes
        // never matched on macOS, so they're gone.)
        .onKeyPress(.space) {
            guard !isSearchFieldFocused else { return .ignored }
            viewModel.selectNext(context: modelContext)
            return .handled
        }
        .onKeyPress("d") {
            guard !isSearchFieldFocused else { return .ignored }
            if let item = viewModel.selectedItem {
                viewModel.toggleRead(item, context: modelContext)
            }
            return .handled
        }
        .onKeyPress("s") {
            guard !isSearchFieldFocused else { return .ignored }
            if let item = viewModel.selectedItem {
                viewModel.toggleStarred(item, context: modelContext)
            }
            return .handled
        }
    }
}

private struct ArticleListRow: View {
    let item: ArticleListItem
    let isSelected: Bool
    let showThumbnails: Bool
    let onSelect: () -> Void
    let onToggleStar: () -> Void
    @AppStorage("showReadingTime") private var showReadingTime: Bool = true
    @Environment(\.colorScheme) private var colorScheme
    /// Three-column layout: the thumbnail sits ABOVE the headline and
    /// summary at the full column width. The stacked layout keeps the
    /// side-by-side row (thumbnail left of the text) — unchanged.
    var showsThumbnailAbove: Bool = false

    var body: some View {
        Group {
            if showsThumbnailAbove {
                // Card-style row: full-width banner over the headline and
                // summary — mirrors the example reader's column cards.
                VStack(alignment: .leading, spacing: 10) {
                    thumbnail
                    textContent
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    thumbnail
                    textContent
                }
            }
        }
        .padding(PrecisSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The whole row is tappable, so ONE press anywhere on it selects the
        // article and (via the view model) marks it read.
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        // Highlight the selected row: accent tint under the leading accent bar.
        .background(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3)
            }
        }
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(PrecisDesignSystem.rule(for: colorScheme)),
            alignment: .bottom
        )
    }

    /// The headline block — title row plus summary — the text half of the
    /// row in both layouts.
    private var textContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                if showsThumbnailAbove {
                    // Card mode (three-column layout): headline and star, with
                    // no unread dot, source, reading time or age crowding the
                    // headline. The headline owns the full first line and only
                    // wraps to a second line once that line is full.
                    Text(item.title)
                        .font(PrecisTypography.headline)
                        .foregroundStyle(item.isRead ? Color.gray : PrecisDesignSystem.foreground(for: colorScheme))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    starButton
                } else {
                    if !item.isRead {
                        Circle()
                            .frame(width: 8, height: 8)
                            .foregroundStyle(Color.accentColor)
                    }

                    // Headline with the source name inline to its right,
                    // baseline-aligned so it sits on the headline's first line.
                    HStack(alignment: .firstTextBaseline, spacing: PrecisSpacing.sm) {
                        Text(item.title)
                            .font(PrecisTypography.headline)
                            .foregroundStyle(item.isRead ? Color.gray : PrecisDesignSystem.foreground(for: colorScheme))
                            .lineLimit(2)

                        Text(FeedDiscoveryService.conciseTitle(item.feedTitle))
                            .font(PrecisTypography.metadata)
                            .foregroundStyle(PrecisDesignSystem.marginalia)

                        if showReadingTime {
                            Text("•")
                                .font(PrecisTypography.metadata)
                                .foregroundStyle(Color.accentColor)

                            Text("\(item.readingTimeMinutes) min read")
                                .font(PrecisTypography.metadata)
                                .foregroundStyle(PrecisDesignSystem.marginalia.opacity(0.7))
                        }
                    }

                    Spacer()

                    Text(publishedAgo(item.publishedDate))
                        .font(PrecisTypography.metadata)
                        .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.5))

                    starButton
                }
            }

            // Summary sits under the headline in both layouts.
            Text(item.cleanSnippet)
                .font(PrecisTypography.body)
                .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.75))
                .lineLimit(2)
        }
    }

    /// The row's star toggle, shared by both layouts.
    private var starButton: some View {
        Button(action: onToggleStar) {
            Image(systemName: item.isStarred ? "star.fill" : "star")
                .foregroundStyle(item.isStarred ? Color.accentColor : PrecisDesignSystem.foreground(for: colorScheme).opacity(0.6))
        }
        .buttonStyle(.plain)
    }

    /// The thumbnail, placed where the current layout calls for it — beside
    /// the text (stacked) or above it at full width (three-column). Absent
    /// when thumbnails are off or the article has no image.
    @ViewBuilder
    private var thumbnail: some View {
        if showThumbnails, let imageURLString = item.imageURL, let imageURL = URL(string: imageURLString) {
            ArticleThumbnailView(url: imageURL, style: showsThumbnailAbove ? .banner : .row)
        }
    }

    /// Compact approximate "time ago" for the row's right edge — "4h", "12m",
    /// "3d"; falls back to a short date ("Sep 5") past a week.
    private func publishedAgo(_ date: Date?) -> String {
        guard let date else { return "" }
        let seconds = max(0, Date().timeIntervalSince(date))
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = Int((seconds / 3600).rounded())
        if hours < 24 { return "\(hours)h" }
        if seconds < 7 * 86_400 {
            return "\(max(1, Int((seconds / 86_400).rounded())))d"
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// Fixed 128×64pt row thumbnail (stacked layout) and full-column-width 2:1
/// banner (three-column layout) that decode at THUMBNAIL resolution.
///
/// `AsyncImage` decodes the article image at full resolution — the sample
/// showed ImageIO decode + `CA::Render::copy_image` IOSurface copies on the
/// `SwiftUI.prepare-image` queues for every row. Across a busy list that
/// churns hundreds of MB of bitmaps and shows up as black windows and mouse
/// trails under memory pressure. This loads the bytes once and downsamples
/// (256px row / 768px banner, 2× Retina) during decode, caching only the
/// small result.
private struct ArticleThumbnailView: View {
    enum Style {
        /// Fixed 128×64pt landscape thumb to the LEFT of the text — the
        /// stacked layout's row.
        case row
        /// Full-column-width 2:1 banner ABOVE the headline/summary — the
        /// three-column layout's card, re-scaled by the column divider drag.
        case banner
    }

    let url: URL
    var style: Style = .row
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: NSImage?

    var body: some View {
        switch style {
        case .row:
            rowThumbnail
        case .banner:
            bannerThumbnail
        }
    }

    private var rowThumbnail: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .frame(width: 128, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.top, 4)
        .task(id: "\(url)-row") {
            image = await ArticleThumbnailLoader.image(
                for: url, maxPixelSize: 256, pointSize: NSSize(width: 128, height: 64)
            )
        }
    }

    /// The banner fills the column: `aspectRatio(2, .fit)` sizes it to
    /// (proposed width × width/2), so dragging the column divider scales
    /// the image with the column. The surface + photo glyph show until the
    /// decode finishes.
    private var bannerThumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(PrecisDesignSystem.surface(for: colorScheme))
                .overlay {
                    if image == nil {
                        Image(systemName: "photo")
                            .foregroundStyle(PrecisDesignSystem.marginalia.opacity(0.3))
                            .font(.title3)
                    }
                }
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .aspectRatio(2, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.top, 4)
        .task(id: "\(url)-banner") {
            image = await ArticleThumbnailLoader.image(for: url, maxPixelSize: 768, pointSize: nil)
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(PrecisDesignSystem.surface(for: colorScheme))
            .frame(width: 128, height: 64)
            .overlay(
                Image(systemName: "photo")
                    .foregroundStyle(PrecisDesignSystem.marginalia.opacity(0.3))
                    .font(.title3)
            )
    }
}

private enum ArticleThumbnailLoader {
    // NSCache is internally thread-safe; the global needs `nonisolated(unsafe)`
    // to satisfy Swift 6 strict concurrency (same pattern as the renderer cache).
    // Keyed by URL + requested pixel size so the 128×64 row thumb and the
    // full-width banner decode separately; the 48 MB budget holds both
    // variants without churning the network refetch path.
    nonisolated(unsafe) static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 500
        cache.totalCostLimit = 48 * 1024 * 1024 // 48 MB of decoded pixels
        return cache
    }()

    /// - Parameter maxPixelSize: longest-edge cap for the decode — 256 for
    ///   the 128×64pt row thumb (2× Retina), 768 for the full-column banner.
    /// - Parameter pointSize: the NSImage point size; nil keeps the decoded
    ///   pixel dimensions (the banner's aspect comes from the image itself).
    static func image(for url: URL, maxPixelSize: Int, pointSize: NSSize?) async -> NSImage? {
        let key = "\(url.absoluteString)|\(maxPixelSize)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let size = pointSize ?? NSSize(width: cgImage.width, height: cgImage.height)
        let nsImage = NSImage(cgImage: cgImage, size: size)
        cache.setObject(
            nsImage,
            forKey: key,
            cost: cgImage.width * cgImage.height * 4
        )
        return nsImage
    }
}

#Preview {
    ArticleListView(viewModel: ArticleListViewModel())
}

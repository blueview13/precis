import SwiftUI
import ImageIO

struct ArticleListView: View {
    @ObservedObject var viewModel: ArticleListViewModel
    /// Set by the shell so the sidebar can be revealed again from the list
    /// header while the sidebar itself is hidden.
    var isSidebarHidden: Bool = false
    var onRevealSidebar: (() -> Void)? = nil
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

                Text("Inbox")
                    .font(PrecisTypography.headline)
                    .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))

                Spacer()

                if viewModel.filteredItems.contains(where: { !$0.isRead }) {
                    Button(action: {
                        let visibleArticleIDs = Set(viewModel.filteredItems.map(\.id))
                        viewModel.markAllAsRead(context: modelContext, articleIDs: visibleArticleIDs)
                    }) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(PrecisDesignSystem.marginalia)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Mark visible articles as read")
                }

                if viewModel.filteredItems.contains(where: { $0.isRead }) {
                    Button(action: {
                        let visibleArticleIDs = Set(viewModel.filteredItems.map(\.id))
                        viewModel.markAllAsUnread(context: modelContext, articleIDs: visibleArticleIDs)
                    }) {
                        Image(systemName: "envelope.badge")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(PrecisDesignSystem.marginalia)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Mark visible articles as unread")
                }
            }
            .padding(PrecisSpacing.md)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(PrecisDesignSystem.marginalia)
                    .font(.caption)

                TextField("Search articles...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(PrecisTypography.body)
                    .focused($isSearchFieldFocused)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(PrecisDesignSystem.rule(for: colorScheme), lineWidth: 1)
            )
            .padding(.horizontal, PrecisSpacing.md)
            .padding(.bottom, PrecisSpacing.sm)

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
                                onToggleStar: { viewModel.toggleStarred(item, context: modelContext) }
                            )
                            .contentShape(Rectangle())
                        }
                    }
                }
            }
            // Rebuild the scroll view when the sidebar filter changes so the
            // new list opens at its top — a preserved offset landed on an
            // arbitrary mid-list article instead.
            .id(viewModel.selectedSidebarFilter)
        }
        .background(PrecisDesignSystem.background(for: colorScheme))
        .focusable()
        // Suppress the system-accent focus ring — with a green macOS accent it
        // painted green borders along the list's left/bottom edges. Keyboard
        // nav (arrows/d/s) still works; selection shows via the row flag bar.
        .focusEffectDisabled(true)
        .onKeyPress(.upArrow) {
            guard !isSearchFieldFocused else { return .ignored }
            viewModel.selectPrevious()
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !isSearchFieldFocused else { return .ignored }
            viewModel.selectNext()
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

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if showThumbnails, let imageURLString = item.imageURL, let imageURL = URL(string: imageURLString) {
                ArticleThumbnailView(url: imageURL)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
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

                    Button(action: onToggleStar) {
                        Image(systemName: item.isStarred ? "star.fill" : "star")
                            .foregroundStyle(item.isStarred ? Color.accentColor : PrecisDesignSystem.foreground(for: colorScheme).opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }

                Text(item.cleanSnippet)
                    .font(PrecisTypography.body)
                    .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.75))
                    .lineLimit(2)
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

/// 128×64pt landscape row thumbnail (roughly 2:1, matching the wide
/// thumbnails in the design reference) that decodes at THUMBNAIL resolution.
///
/// `AsyncImage` decodes the article image at full resolution — the sample
/// showed ImageIO decode + `CA::Render::copy_image` IOSurface copies on the
/// `SwiftUI.prepare-image` queues for every row. Across a busy list that
/// churns hundreds of MB of bitmaps and shows up as black windows and mouse
/// trails under memory pressure. This loads the bytes once and downsamples
/// to 256px (2× for Retina) during decode, caching only the small result.
private struct ArticleThumbnailView: View {
    let url: URL
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: NSImage?

    var body: some View {
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
        .task(id: url) {
            image = await ArticleThumbnailLoader.image(for: url)
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
    nonisolated(unsafe) static let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 400
        cache.totalCostLimit = 24 * 1024 * 1024 // 24 MB of decoded pixels
        return cache
    }()

    static func image(for url: URL) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 256
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 128, height: 64))
        cache.setObject(
            nsImage,
            forKey: url as NSURL,
            cost: cgImage.width * cgImage.height * 4
        )
        return nsImage
    }
}

#Preview {
    ArticleListView(viewModel: ArticleListViewModel())
}

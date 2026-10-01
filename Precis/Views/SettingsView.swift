import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage(PrecisTheme.storageKey) private var selectedThemeRawValue = PrecisTheme.standard.rawValue
    @AppStorage("readingFontSize") private var readingFontSize: Double = 15
    @AppStorage("summaryAutoGenerate") private var summaryAutoGenerate: Bool = false
    @AppStorage("refreshIntervalMinutes") private var refreshIntervalMinutes: Int = 15
    @AppStorage("defaultSortOrder") private var defaultSortOrder: String = "newest"
    @AppStorage("showReadingTime") private var showReadingTime: Bool = true
    @AppStorage("showThumbnails") private var showThumbnails: Bool = true
    @AppStorage("showArticleImages") private var showArticleImages: Bool = true
    @State private var opmlStatus = ""
    @State private var opmlStatusIsError = false
    /// 0…1 fill of the OPML progress bar; nil while no import/export runs.
    @State private var opmlProgress: Double? = nil
    /// Locks both OPML buttons while an import/export is in flight.
    @State private var isOPMLBusy = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    private var selectedTheme: PrecisTheme {
        PrecisTheme(rawValue: selectedThemeRawValue) ?? .standard
    }

    let onImportOPML: (() -> Void)?
    let onExportOPML: (() -> Void)?
    let hasFeeds: Bool

    private let refreshOptions = [1, 5, 15, 30, 60]
    private let sortOptions = ["newest", "oldest", "unread first", "starred first"]

    private var feedCount: Int {
        do {
            return try FeedRepository().fetchAll(context: modelContext).count
        } catch {
            return 0
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar area — leaves room for traffic lights
            HStack {
                Text("Settings")
                    .font(PrecisTypography.headline)
                    .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))
                Spacer()
            }
            .padding(.horizontal, PrecisSpacing.lg)
            .padding(.top, PrecisSpacing.md)
            .padding(.bottom, PrecisSpacing.sm)

            Divider()
                .background(PrecisDesignSystem.rule(for: colorScheme))

            ScrollView {
                VStack(alignment: .leading, spacing: PrecisSpacing.lg) {
                    settingsSection(title: "Appearance") {
                        VStack(spacing: PrecisSpacing.xs) {
                            ForEach(PrecisTheme.allCases) { theme in
                                Button {
                                    selectedThemeRawValue = theme.rawValue
                                } label: {
                                    HStack(spacing: PrecisSpacing.sm) {
                                        themePreview(theme)

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(theme.name)
                                                .font(PrecisTypography.body.weight(.medium))
                                                .foregroundStyle(selectedTheme.foreground)
                                            Text(theme.detail)
                                                .font(PrecisTypography.caption)
                                                .foregroundStyle(selectedTheme.foreground.opacity(0.65))
                                        }

                                        Spacer(minLength: PrecisSpacing.xs)

                                        if selectedTheme == theme {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(theme.accent)
                                        }
                                    }
                                    .padding(PrecisSpacing.xs)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        selectedTheme == theme ? theme.accent.opacity(0.08) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedTheme == theme ? theme.accent : theme.rule, lineWidth: 1)
                                    }
                                    .contentShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    settingsSection(title: "Reading") {
                        VStack(alignment: .leading, spacing: PrecisSpacing.md) {
                            HStack {
                                Text("Reading pane font size")
                                    .font(PrecisTypography.body)
                                    .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))
                                Spacer()
                                Text("\(Int(readingFontSize))pt")
                                    .font(PrecisTypography.metadata)
                                    .foregroundStyle(PrecisDesignSystem.marginalia)
                            }
                            Slider(value: $readingFontSize, in: 12...24, step: 1)

                            Toggle("Show reading time estimates", isOn: $showReadingTime)
                                .font(PrecisTypography.body)
                                .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))
                        }
                    }

                    settingsSection(title: "Article List") {
                        VStack(alignment: .leading, spacing: PrecisSpacing.sm) {
                            Toggle("Show article thumbnails", isOn: $showThumbnails)
                                .font(PrecisTypography.body)
                                .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))

                            Toggle("Show article images", isOn: $showArticleImages)
                                .font(PrecisTypography.body)
                                .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))

                            Text("Default sort order")
                                .font(PrecisTypography.body)
                                .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))

                            Picker("", selection: $defaultSortOrder) {
                                ForEach(sortOptions, id: \.self) { option in
                                    Text(option.capitalized).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    settingsSection(title: "AI Summaries") {
                        Toggle("Auto-generate summaries on open", isOn: $summaryAutoGenerate)
                            .font(PrecisTypography.body)
                            .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))
                    }

                    settingsSection(title: "Refresh") {
                        VStack(alignment: .leading, spacing: PrecisSpacing.sm) {
                            Text("Background refresh interval")
                                .font(PrecisTypography.body)
                                .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))

                            Picker("", selection: $refreshIntervalMinutes) {
                                ForEach(refreshOptions, id: \.self) { minutes in
                                    Text("\(minutes) min").tag(minutes)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    settingsSection(title: "OPML") {
                        VStack(alignment: .leading, spacing: PrecisSpacing.sm) {
                            // Compact paired buttons — same `.bordered` style as
                            // the reading pane's actions, rather than two
                            // full-width slabs.
                            HStack(spacing: PrecisSpacing.xs) {
                                Button(action: {
                                    if let onImportOPML {
                                        onImportOPML()
                                    } else {
                                        performImportOPML()
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.up.doc")
                                            .font(.caption)
                                        Text("Import OPML")
                                            .font(PrecisTypography.metadata)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(isOPMLBusy)

                                let canExport = hasFeeds || feedCount > 0
                                Button(action: {
                                    if let onExportOPML {
                                        onExportOPML()
                                    } else {
                                        performExportOPML()
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.down.doc")
                                            .font(.caption)
                                        Text("Export OPML")
                                            .font(PrecisTypography.metadata)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(!canExport || isOPMLBusy)

                                Spacer(minLength: 0)
                            }

                            if opmlProgress != nil || !opmlStatus.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    if let progress = opmlProgress {
                                        ProgressView(value: progress)
                                            .progressViewStyle(.linear)
                                            .tint(PrecisDesignSystem.marginalia)
                                            .animation(.easeInOut(duration: 0.2), value: progress)
                                    }
                                    if !opmlStatus.isEmpty {
                                        Text(opmlStatus)
                                            .font(PrecisTypography.metadata)
                                            .foregroundStyle(opmlStatusIsError ? Color.red : PrecisDesignSystem.marginalia)
                                            .lineLimit(3)
                                    }
                                }
                            }
                        }
                    }

                    Spacer()
                }
                .padding(PrecisSpacing.lg)
            }
        }
        .background(PrecisDesignSystem.background(for: colorScheme))
        .preferredColorScheme(selectedTheme.colorScheme)
        .tint(selectedTheme.accent)
    }

    private func themePreview(_ theme: PrecisTheme) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                Circle().fill(theme.flag).frame(width: 4, height: 4)
                Circle().fill(theme.rule).frame(width: 4, height: 4)
                Circle().fill(theme.rule).frame(width: 4, height: 4)
                Spacer()
                RoundedRectangle(cornerRadius: 1).fill(theme.rule).frame(width: 19, height: 3)
            }

            HStack(spacing: 5) {
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1).fill(theme.accent).frame(height: 4)
                    RoundedRectangle(cornerRadius: 1).fill(theme.rule).frame(height: 3)
                    RoundedRectangle(cornerRadius: 1).fill(theme.rule).frame(height: 3)
                }
                .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 1).fill(theme.foreground.opacity(0.75)).frame(width: 36, height: 4)
                    RoundedRectangle(cornerRadius: 1).fill(theme.rule).frame(height: 3)
                    RoundedRectangle(cornerRadius: 1).fill(theme.rule).frame(width: 27, height: 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(6)
        .frame(width: 82, height: 48)
        .background(theme.background, in: RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(theme.rule, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private func performImportOPML() {
        let panel = NSOpenPanel()
        panel.title = "Import OPML"
        panel.allowedContentTypes = [.xml, .text, .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            opmlStatus = "Reading OPML file…"
            opmlStatusIsError = false
            isOPMLBusy = true
            opmlProgress = 0
            Task { @MainActor in
                defer {
                    isOPMLBusy = false
                    opmlProgress = nil
                }
                do {
                    let opmlFeeds = try OPMLService.parse(contentsOf: url)
                    guard !opmlFeeds.isEmpty else {
                        opmlStatus = "No feeds found in that OPML file"
                        opmlStatusIsError = true
                        return
                    }
                    let feedRepository = FeedRepository()
                    let articleRepository = ArticleRepository()
                    let refreshService = FeedRefreshService()
                    let total = opmlFeeds.count

                    // Skip URLs already subscribed so re-importing a file is
                    // a no-op instead of duplicating every feed.
                    let existing = (try? feedRepository.fetchAll(context: modelContext)) ?? []
                    var seenURLs = Set(existing.map(\.url))
                    var added = 0
                    var processed = 0

                    for opmlFeed in opmlFeeds {
                        defer {
                            processed += 1
                            opmlProgress = Double(processed) / Double(total)
                            opmlStatus = "Imported \(processed) of \(total) feeds"
                        }
                        guard seenURLs.insert(opmlFeed.url).inserted else {
                            // Duplicates never suspend — yield so the bar still repaints.
                            await Task.yield()
                            continue
                        }
                        let feed = try feedRepository.create(
                            title: opmlFeed.title,
                            url: opmlFeed.url,
                            folder: nil,
                            context: modelContext
                        )
                        added += 1
                        if let feedURL = URL(string: opmlFeed.url) {
                            do {
                                let resolved = await FeedDiscoveryService.resolveFeedURL(feedURL)
                                let parsed = try await refreshService.fetchAndParse(
                                    Feed(title: opmlFeed.title, url: resolved)
                                )
                                // Persist the resolved feed URL so future
                                // refreshes fetch the XML directly instead of
                                // repeating discovery on the home page.
                                if resolved.absoluteString != feed.url {
                                    feed.url = resolved.absoluteString
                                }
                                // Use the feed's real channel title when the
                                // OPML entry only carried a URL
                                let displayTitle = FeedDiscoveryService.displayTitle(current: feed.title, parsedTitle: parsed.title)
                                if displayTitle != feed.title {
                                    feed.title = displayTitle
                                }
                                try modelContext.save()
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
                                // Feed still imported without articles.
                                PrecisLogger.error("OPML: could not fetch \(opmlFeed.url) — \(error.localizedDescription)")
                            }
                        }
                    }

                    opmlStatus = added > 0
                        ? "Imported \(added) feed\(added == 1 ? "" : "s") (\(opmlFeeds.count - added) already subscribed)"
                        : "All \(opmlFeeds.count) feeds were already subscribed"
                    opmlStatusIsError = false
                    PrecisLogger.info("OPML import finished: \(added) added of \(opmlFeeds.count)")
                    // Tell the main window to reload its sidebar feed list.
                    NotificationCenter.default.post(name: .precisFeedsImported, object: nil)
                } catch {
                    PrecisLogger.error("OPML import failed: \(error.localizedDescription)")
                    opmlStatus = "OPML import failed: \(error.localizedDescription)"
                    opmlStatusIsError = true
                }
            }
        }
    }

    private func performExportOPML() {
        let panel = NSSavePanel()
        panel.title = "Export OPML"
        panel.nameFieldStringValue = "Precis-Subscriptions.opml"
        panel.allowedContentTypes = [.xml, .data]

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            isOPMLBusy = true
            opmlProgress = 0
            opmlStatusIsError = false
            Task { @MainActor in
                defer {
                    isOPMLBusy = false
                    opmlProgress = nil
                }
                do {
                    let feeds = try FeedRepository().fetchAll(context: modelContext)
                    let total = feeds.count
                    // Serialize in small steps so the bar reflects real work
                    // instead of jumping 0 → 100 at the end.
                    var opmlFeeds: [OPMLFeed] = []
                    opmlFeeds.reserveCapacity(total)
                    for (index, feed) in feeds.enumerated() {
                        opmlFeeds.append(OPMLFeed(title: feed.title, url: feed.url, folderName: feed.folder?.name))
                        opmlProgress = Double(index + 1) / Double(max(total, 1))
                        opmlStatus = "Exported \(index + 1) of \(total) feeds"
                        if index % 16 == 15 { await Task.yield() }
                    }
                    let xml = OPMLService.generate(feeds: opmlFeeds)
                    try xml.write(to: url, atomically: true, encoding: .utf8)
                    opmlStatus = "Exported \(total) feed\(total == 1 ? "" : "s")"
                } catch {
                    PrecisLogger.error("OPML export failed: \(error.localizedDescription)")
                    opmlStatus = "Export failed: \(error.localizedDescription)"
                    opmlStatusIsError = true
                }
            }
        }
    }

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PrecisSpacing.sm) {
            Text(title.uppercased())
                .font(PrecisTypography.caption)
                .foregroundStyle(PrecisDesignSystem.marginalia)
                .tracking(1.2)

            Divider()
                .background(PrecisDesignSystem.rule(for: colorScheme))

            content()
                .padding(.top, PrecisSpacing.xs)
        }
    }
}

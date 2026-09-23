import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage("readingFontSize") private var readingFontSize: Double = 15
    @AppStorage("summaryAutoGenerate") private var summaryAutoGenerate: Bool = false
    @AppStorage("refreshIntervalMinutes") private var refreshIntervalMinutes: Int = 15
    @AppStorage("defaultSortOrder") private var defaultSortOrder: String = "newest"
    @AppStorage("showReadingTime") private var showReadingTime: Bool = true
    @AppStorage("showThumbnails") private var showThumbnails: Bool = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    let onImportOPML: (() -> Void)?
    let onExportOPML: (() -> Void)?
    let hasFeeds: Bool

    private let refreshOptions = [5, 15, 30, 60]
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
                    settingsSection(title: "Reading") {
                        VStack(alignment: .leading, spacing: PrecisSpacing.md) {
                            HStack {
                                Text("Font size")
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
                            Button(action: {
                                if let onImportOPML {
                                    onImportOPML()
                                } else {
                                    performImportOPML()
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.up.doc")
                                    Text("Import OPML")
                                }
                                .font(PrecisTypography.body)
                                .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(PrecisDesignSystem.surface(for: colorScheme))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)

                            let canExport = hasFeeds || feedCount > 0
                            Button(action: {
                                if let onExportOPML {
                                    onExportOPML()
                                } else {
                                    performExportOPML()
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.down.doc")
                                    Text("Export OPML")
                                }
                                .font(PrecisTypography.body)
                                .foregroundStyle(canExport ? PrecisDesignSystem.foreground(for: colorScheme) : PrecisDesignSystem.foreground(for: colorScheme).opacity(0.4))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(PrecisDesignSystem.surface(for: colorScheme))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .disabled(!canExport)
                        }
                    }

                    Spacer()
                }
                .padding(PrecisSpacing.lg)
            }
        }
        .background(PrecisDesignSystem.background(for: colorScheme))
    }

    private func performImportOPML() {
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

                    for opmlFeed in opmlFeeds {
                        let feed = try feedRepository.create(
                            title: opmlFeed.title,
                            url: opmlFeed.url,
                            folder: nil,
                            context: modelContext
                        )
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
                            } catch {}
                        }
                    }
                } catch {}
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
            do {
                let feeds = try FeedRepository().fetchAll(context: modelContext)
                let opmlFeeds = feeds.map { OPMLFeed(title: $0.title, url: $0.url, folderName: $0.folder?.name) }
                let xml = OPMLService.generate(feeds: opmlFeeds)
                try xml.write(to: url, atomically: true, encoding: .utf8)
            } catch {}
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

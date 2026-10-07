import SwiftUI
import AppKit
import SwiftData

@MainActor
private final class DesktopPanelColorPanelController: NSObject {
    private var onColorChange: ((NSColor) -> Void)?

    func present(
        initialColor: NSColor,
        relativeTo settingsWindow: NSWindow?,
        onColorChange: @escaping (NSColor) -> Void
    ) {
        self.onColorChange = onColorChange
        let panel = NSColorPanel.shared
        panel.color = initialColor
        panel.setTarget(self)
        panel.setAction(#selector(colorDidChange(_:)))

        if let settingsWindow,
           let screen = settingsWindow.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            let size = panel.frame.size
            let leftX = settingsWindow.frame.minX - size.width - 12
            let rightX = settingsWindow.frame.maxX + 12
            let x: CGFloat
            if leftX >= visible.minX {
                x = leftX
            } else if rightX + size.width <= visible.maxX {
                x = rightX
            } else {
                x = visible.minX + (visible.width - size.width) / 2
            }
            let y = min(max(settingsWindow.frame.midY - size.height / 2, visible.minY), visible.maxY - size.height)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.orderFront(nil)
    }

    @objc private func colorDidChange(_ sender: NSColorPanel) {
        onColorChange?(sender.color)
    }
}

/// Fires `onWindowWillClose` when the window this view sits in is about to
/// close — used to dismiss the shared colour picker along with its owner.
private struct WindowWillCloseObserver: NSViewRepresentable {
    let onWindowWillClose: () -> Void

    func makeNSView(context: Context) -> WindowWillCloseView {
        WindowWillCloseView(onWindowWillClose: onWindowWillClose)
    }

    func updateNSView(_ nsView: WindowWillCloseView, context: Context) {}

    final class WindowWillCloseView: NSView {
        let onWindowWillClose: () -> Void
        // Written on the main thread only (view attachment) and torn down in
        // deinit; the token itself is just an observer handle.
        nonisolated(unsafe) private var observer: NSObjectProtocol?

        init(onWindowWillClose: @escaping () -> Void) {
            self.onWindowWillClose = onWindowWillClose
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard observer == nil, let window else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.onWindowWillClose()
            }
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}

struct SettingsView: View {
    @AppStorage(PrecisTheme.storageKey) private var selectedThemeRawValue = PrecisTheme.standard.rawValue
    @AppStorage("readingFontSize") private var readingFontSize: Double = 15
    @AppStorage("readingContentWidth") private var readingContentWidth: Double = 750
    @AppStorage("showSidebarUnreadPills") private var showSidebarUnreadPills: Bool = true
    // Default On, matching the launch behaviour it gates — users opt out.
    @AppStorage("summaryAutoGenerate") private var summaryAutoGenerate: Bool = true
    @AppStorage("refreshIntervalMinutes") private var refreshIntervalMinutes: Int = 15
    @AppStorage("defaultSortOrder") private var defaultSortOrder: String = "newest"
    @AppStorage("showReadingTime") private var showReadingTime: Bool = true
    @AppStorage("showThumbnails") private var showThumbnails: Bool = true
    @AppStorage("showArticleImages") private var showArticleImages: Bool = true
    @AppStorage("notifyOnNewArticles") private var notifyOnNewArticles = false
    @AppStorage("desktopPanelEnabled") private var desktopPanelEnabled = false
    @AppStorage("desktopPanelEdge") private var desktopPanelEdge = "right"
    @AppStorage("desktopPanelBackground") private var desktopPanelBackground = "#FFFFFF"
    @AppStorage("desktopPanelTextColor") private var desktopPanelTextColor = "#000000"
    @AppStorage("desktopPanelOpacity") private var desktopPanelOpacity = 0.7
    @AppStorage("desktopPanelSources") private var desktopPanelSources = "*"
    @AppStorage("desktopPanelArticleLimit") private var desktopPanelArticleLimit = 50
    @AppStorage("desktopPanelSmartCategories") private var desktopPanelSmartCategories = ""
    @State private var opmlStatus = ""
    @State private var opmlStatusIsError = false
    @State private var notificationPermissionMessage = ""
    @State private var notificationPermissionIsError = false
    /// 0…1 fill of the OPML progress bar; nil while no import/export runs.
    @State private var opmlProgress: Double? = nil
    /// Locks both OPML buttons while an import/export is in flight.
    @State private var isOPMLBusy = false
    @State private var feedbinUsername = ""
    @State private var feedbinPassword = ""
    @State private var feedbinStatus = ""
    @State private var feedbinBusy = false
    @State private var hasFeedbinCredentials = false
    @AppStorage("feedbinUsername") private var savedFeedbinUsername = ""
    @State private var desktopPanelFeeds: [FeedRecord] = []
    @State private var desktopPanelFolders: [FolderRecord] = []
    @State private var isDesktopPanelFoldersExpanded = false
    @State private var isDesktopPanelFeedsExpanded = false
    @State private var isDesktopPanelSmartCategoriesExpanded = false
    @ObservedObject private var smartCategoryStore = SmartCategoryStore.shared
    @State private var desktopPanelColorPanel = DesktopPanelColorPanelController()
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

                            HStack {
                                Text("Reading pane content width")
                                    .font(PrecisTypography.body)
                                    .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))
                                Spacer()
                                Text("\(Int(readingContentWidth))px")
                                    .font(PrecisTypography.metadata)
                                    .foregroundStyle(PrecisDesignSystem.marginalia)
                            }
                            Slider(value: $readingContentWidth, in: 500...1200, step: 50)

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

                    settingsSection(title: "Left Sidebar") {
                        Toggle("Show unread count on feeds", isOn: $showSidebarUnreadPills)
                            .font(PrecisTypography.body)
                            .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))
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

                    settingsSection(title: "Feedbin") {
                        VStack(alignment: .leading, spacing: PrecisSpacing.sm) {
                            Text("Connect your Feedbin account to show its subscriptions and tags in the sidebar.")
                                .font(PrecisTypography.caption)
                                .foregroundStyle(PrecisDesignSystem.marginalia)
                            TextField("Feedbin email", text: $feedbinUsername)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.username)
                            SecureField("Feedbin password", text: $feedbinPassword)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.password)
                            HStack {
                                Button(feedbinBusy ? "Syncing…" : "Connect and Sync") { connectFeedbin() }
                                    .disabled(feedbinBusy || feedbinUsername.isEmpty || feedbinPassword.isEmpty)
                                if hasFeedbinCredentials {
                                    Button("Disconnect") {
                                        Task {
                                            await FeedbinCredentialStore.delete()
                                            hasFeedbinCredentials = false
                                            feedbinPassword = ""
                                            savedFeedbinUsername = ""
                                            feedbinStatus = "Feedbin disconnected. Synced feeds remain in Precis."
                                            NotificationCenter.default.post(name: .precisFeedsImported, object: nil)
                                            NotificationCenter.default.post(name: .precisFeedbinDisconnected, object: nil)
                                        }
                                    }
                                }
                            }
                            if !feedbinStatus.isEmpty {
                                Text(feedbinStatus)
                                    .font(PrecisTypography.caption)
                                    .foregroundStyle(feedbinStatus.lowercased().contains("failed") ? .red : PrecisDesignSystem.marginalia)
                            }
                        }
                    }

                    settingsSection(title: "Notifications") {
                        VStack(alignment: .leading, spacing: PrecisSpacing.xs) {
                            Toggle("Notify when new articles arrive", isOn: $notifyOnNewArticles)
                                .font(PrecisTypography.body)
                                .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))
                                .onChange(of: notifyOnNewArticles) { _, isEnabled in
                                    guard isEnabled else {
                                        notificationPermissionMessage = ""
                                        return
                                    }
                                    Task {
                                        do {
                                            let authorized = try await NewArticleNotificationService.requestAuthorization()
                                            if !authorized {
                                                notificationPermissionIsError = true
                                                notificationPermissionMessage = "Allow notifications for Precis in System Settings to receive alerts."
                                            } else {
                                                notificationPermissionIsError = false
                                                notificationPermissionMessage = await NewArticleNotificationService.settingsGuidance() ?? ""
                                            }
                                        } catch {
                                            notificationPermissionIsError = true
                                            notificationPermissionMessage = "Could not enable notifications: \(error.localizedDescription)"
                                        }
                                    }
                                }

                            if !notificationPermissionMessage.isEmpty {
                                Text(notificationPermissionMessage)
                                    .font(PrecisTypography.caption)
                                    .foregroundStyle(notificationPermissionIsError ? Color.red : PrecisDesignSystem.marginalia)
                            }
                        }
                        .task {
                            guard notifyOnNewArticles else { return }
                            notificationPermissionMessage = await NewArticleNotificationService.settingsGuidance() ?? ""
                            notificationPermissionIsError = notificationPermissionMessage.hasPrefix("Allow notifications")
                        }
                    }

                    settingsSection(title: "Desktop Edge Panel") {
                        VStack(alignment: .leading, spacing: PrecisSpacing.md) {
                            Toggle("Show menu bar headlines", isOn: $desktopPanelEnabled)
                                .font(PrecisTypography.body)

                            Picker("Screen edge", selection: $desktopPanelEdge) {
                                Text("Left").tag("left")
                                Text("Right").tag("right")
                            }
                            .pickerStyle(.segmented)

                            VStack(alignment: .leading, spacing: PrecisSpacing.xs) {
                                HStack {
                                    Text("Articles to show")
                                    Spacer()
                                    Text("\(min(max(desktopPanelArticleLimit, 1), 50))")
                                        .foregroundStyle(PrecisDesignSystem.marginalia)
                                        .monospacedDigit()
                                }
                                Slider(
                                    value: Binding(
                                        get: { Double(min(max(desktopPanelArticleLimit, 1), 50)) },
                                        set: { desktopPanelArticleLimit = Int($0.rounded()) }
                                    ),
                                    in: 1...50,
                                    step: 1
                                )
                                .accessibilityLabel("Number of articles in desktop edge panel")
                            }

                            HStack {
                                Text("Background")
                                Spacer()
                                Button {
                                    desktopPanelColorPanel.present(
                                        initialColor: NSColor(desktopPanelColor.wrappedValue),
                                        relativeTo: NSApp.keyWindow
                                    ) { color in
                                        desktopPanelBackground = PrecisDesignSystem.hexString(from: Color(nsColor: color))
                                    }
                                } label: {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(desktopPanelColor.wrappedValue)
                                        .frame(width: 40, height: 22)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.2), lineWidth: 1)
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Choose panel background color")
                                .help("Choose panel background color")
                            }

                            VStack(alignment: .leading, spacing: PrecisSpacing.xs) {
                                HStack {
                                    Text("Background opacity")
                                    Spacer()
                                    Text("\(Int(desktopPanelOpacity * 100))%")
                                        .foregroundStyle(PrecisDesignSystem.marginalia)
                                }
                                Slider(value: $desktopPanelOpacity, in: 0...1, step: 0.05)
                            }

                            HStack {
                                Text("Article text color")
                                Spacer()
                                Button {
                                    desktopPanelColorPanel.present(
                                        initialColor: NSColor(desktopPanelText.wrappedValue),
                                        relativeTo: NSApp.keyWindow
                                    ) { color in
                                        desktopPanelTextColor = PrecisDesignSystem.hexString(from: Color(nsColor: color))
                                    }
                                } label: {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(desktopPanelText.wrappedValue)
                                        .frame(width: 40, height: 22)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.2), lineWidth: 1)
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Choose article text color")
                                .help("Choose article text color")
                            }

                            if !smartCategoryStore.categories.filter({ !$0.isDeleted }).isEmpty {
                                sourceDisclosure(
                                    "Smart Categories",
                                    isExpanded: $isDesktopPanelSmartCategoriesExpanded
                                ) {
                                    VStack(alignment: .leading, spacing: PrecisSpacing.xs) {
                                        ForEach(smartCategoryStore.categories.filter { !$0.isDeleted }) { category in
                                            smartCategoryToggle(category)
                                        }
                                    }
                                }
                            }

                            if !desktopPanelFolders.isEmpty {
                                sourceDisclosure(
                                    "Folders",
                                    isExpanded: $isDesktopPanelFoldersExpanded
                                ) {
                                    VStack(alignment: .leading, spacing: PrecisSpacing.xs) {
                                        ForEach(desktopPanelFolders) { folder in
                                            sourceToggle(folder.name, feedIDs: folder.feeds.map(\.id))
                                        }
                                    }
                                }
                            }

                            sourceDisclosure(
                                "Feeds",
                                isExpanded: $isDesktopPanelFeedsExpanded
                            ) {
                                VStack(alignment: .leading, spacing: PrecisSpacing.xs) {
                                    ForEach(desktopPanelFeeds) { feed in
                                        sourceToggle(feed.title, feedIDs: [feed.id])
                                    }
                                }
                            }
                        }
                        .font(PrecisTypography.body)
                        .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))
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
        .task {
            loadDesktopPanelSources()
            let credentials = await FeedbinCredentialStore.load()
            feedbinUsername = credentials?.username ?? savedFeedbinUsername
            hasFeedbinCredentials = credentials != nil
        }
        .background(WindowWillCloseObserver {
            // The picker is app-shared and would otherwise float on over the
            // desktop after its owner window is gone.
            NSColorPanel.shared.close()
        })
    }

    private var desktopPanelColor: Binding<Color> {
        Binding(
            get: { PrecisDesignSystem.color(hex: desktopPanelBackground) ?? .white },
            set: { desktopPanelBackground = PrecisDesignSystem.hexString(from: $0) }
        )
    }

    private var desktopPanelText: Binding<Color> {
        Binding(
            get: { PrecisDesignSystem.color(hex: desktopPanelTextColor) ?? .black },
            set: { desktopPanelTextColor = PrecisDesignSystem.hexString(from: $0) }
        )
    }

    private var selectedDesktopFeedIDs: Set<UUID>? {
        guard desktopPanelSources != "*" else { return nil }
        return DesktopPanelFeedSelection.selectedFeedIDs(
            from: desktopPanelSources,
            availableFeedIDs: Set(desktopPanelFeeds.map(\.id))
        )
    }

    private func sourceToggle(_ title: String, feedIDs: [UUID]) -> some View {
        let targetIDs = Set(feedIDs)
        let allFeedIDs = Set(desktopPanelFeeds.map(\.id))
        return HStack(spacing: PrecisSpacing.xs) {
            Toggle("", isOn: Binding(
                get: {
                    guard !targetIDs.isEmpty else { return false }
                    let selected = selectedDesktopFeedIDs ?? allFeedIDs
                    return targetIDs.isSubset(of: selected)
                },
                set: { isSelected in
                    var selected = selectedDesktopFeedIDs ?? allFeedIDs
                    if isSelected {
                        selected.formUnion(targetIDs)
                    } else {
                        selected.subtract(targetIDs)
                    }
                    desktopPanelSources = DesktopPanelFeedSelection.storedValue(
                        for: selected,
                        availableFeedIDs: allFeedIDs
                    )
                }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .accessibilityLabel(title)
            .disabled(targetIDs.isEmpty)

            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func smartCategoryToggle(_ category: SmartCategory) -> some View {
        let selectedIDs = Set(desktopPanelSmartCategories.split(separator: ",").compactMap {
            UUID(uuidString: String($0))
        })
        return HStack(spacing: PrecisSpacing.xs) {
            Toggle("", isOn: Binding(
                get: { selectedIDs.contains(category.id) },
                set: { isSelected in
                    var updated = selectedIDs
                    if isSelected { updated.insert(category.id) }
                    else { updated.remove(category.id) }
                    desktopPanelSmartCategories = updated.map(\.uuidString).sorted().joined(separator: ",")
                }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .accessibilityLabel(category.name)

            Text(category.name)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sourceDisclosure<Content: View>(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: PrecisSpacing.xs) {
            Button {
                isExpanded.wrappedValue.toggle()
            } label: {
                HStack(spacing: PrecisSpacing.xs) {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PrecisDesignSystem.marginalia)
                        .frame(width: 12)
                    Text(title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityHint(isExpanded.wrappedValue ? "Collapse" : "Expand")

            if isExpanded.wrappedValue {
                content()
                    .padding(.leading, 20)
            }
        }
    }

    private func loadDesktopPanelSources() {
        do {
            desktopPanelFeeds = try FeedRepository().fetchAll(context: modelContext).sorted { $0.title < $1.title }
            desktopPanelFolders = try modelContext.fetch(FetchDescriptor<FolderRecord>()).sorted { $0.name < $1.name }
        } catch {
            desktopPanelFeeds = []
            desktopPanelFolders = []
        }
    }

    @MainActor
    private func connectFeedbin() {
        feedbinBusy = true
        feedbinStatus = "Connecting to Feedbin…"
        Task { @MainActor in
            defer { feedbinBusy = false }
            do {
                let credentials = FeedbinCredentials(username: feedbinUsername, password: feedbinPassword)
                let service = FeedbinService(credentials: credentials)
                let added = try await service.sync(context: modelContext)
                try await FeedbinCredentialStore.save(credentials)
                hasFeedbinCredentials = true
                savedFeedbinUsername = credentials.username
                feedbinPassword = ""
                feedbinStatus = "Synced Feedbin. Added \(added) new feed\(added == 1 ? "" : "s")."
                NotificationCenter.default.post(name: .precisFeedsImported, object: nil)
                NotificationCenter.default.post(name: .precisFeedbinConnected, object: nil)
            } catch {
                feedbinStatus = "Feedbin connection failed: \(error.localizedDescription)"
            }
        }
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
                    let refreshService = FeedRefreshService()
                    let total = opmlFeeds.count

                    // Skip URLs already subscribed so re-importing a file is
                    // a no-op instead of duplicating every feed.
                    let existing = (try? feedRepository.fetchAll(context: modelContext)) ?? []
                    var seenURLs = Set(existing.map { FeedRepository.canonicalURLString($0.url) })
                    var added = 0
                    var processed = 0

                    for opmlFeed in opmlFeeds {
                        defer {
                            processed += 1
                            opmlProgress = Double(processed) / Double(total)
                            opmlStatus = "Imported \(processed) of \(total) feeds"
                        }
                        let inputURL = FeedRepository.canonicalURLString(opmlFeed.url)
                        guard seenURLs.insert(inputURL).inserted else {
                            // Duplicates never suspend — yield so the bar still repaints.
                            await Task.yield()
                            continue
                        }
                        let resolvedURL: URL?
                        if let url = URL(string: opmlFeed.url), url.host != nil {
                            resolvedURL = await FeedDiscoveryService.resolveFeedURL(url)
                        } else {
                            resolvedURL = nil
                        }
                        let storedURL = resolvedURL?.absoluteString ?? opmlFeed.url
                        let storedURLKey = FeedRepository.canonicalURLString(storedURL)
                        if storedURLKey != inputURL && !seenURLs.insert(storedURLKey).inserted {
                            continue
                        }
                        let feed = try feedRepository.create(
                            title: opmlFeed.title,
                            url: storedURL,
                            folder: nil,
                            context: modelContext
                        )
                        added += 1
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
                                }
                                try modelContext.save()
                                try await ArticleIngestProcessor().ingestParsed(
                                    parsed.entries,
                                    feedID: feed.id,
                                    container: modelContext.container
                                )
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

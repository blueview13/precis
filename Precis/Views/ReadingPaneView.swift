import SwiftUI
import WebKit
import AppKit

struct ReadingPaneView: View {
    let item: ArticleListItem?
    let summaryOverride: String?
    let feedWideSummary: String?
    let isGeneratingSummary: Bool
    let onGenerateSummary: (() -> Void)?
    let onOpenInBrowser: (() -> Void)?
    /// True while the full article page is being downloaded for the current
    /// selection — shown above the body as "Loading full article…".
    let isFetchingContent: Bool
    /// Moves the selection one article up/down the visible list — wired to
    /// the pane's ‹ › step controls.
    let onPreviousArticle: (() -> Void)?
    let onNextArticle: (() -> Void)?
    /// Whether an article exists above/below the current selection; the
    /// matching chevron greys out when it doesn't.
    let canSelectPrevious: Bool
    let canSelectNext: Bool
    @AppStorage("readingFontSize") private var readingFontSize: Double = 15
    @AppStorage("showReadingTime") private var showReadingTime: Bool = true
    @Environment(\.colorScheme) private var colorScheme
    /// Content height reported by the article web view — it grows as the
    /// document (and its images) finish measuring inside this scroll view.
    @State private var articleHeight: CGFloat = 320
    /// Scroll anchor at the very top of the pane's content — a newly
    /// selected article scrolls back here.
    private static let topAnchorID = "readingPaneTop"

    init(
        item: ArticleListItem?,
        summaryOverride: String? = nil,
        feedWideSummary: String? = nil,
        isGeneratingSummary: Bool = false,
        onGenerateSummary: (() -> Void)? = nil,
        onOpenInBrowser: (() -> Void)? = nil,
        isFetchingContent: Bool = false,
        onPreviousArticle: (() -> Void)? = nil,
        onNextArticle: (() -> Void)? = nil,
        canSelectPrevious: Bool = false,
        canSelectNext: Bool = false
    ) {
        self.item = item
        self.summaryOverride = summaryOverride
        self.feedWideSummary = feedWideSummary
        self.isGeneratingSummary = isGeneratingSummary
        self.onGenerateSummary = onGenerateSummary
        self.onOpenInBrowser = onOpenInBrowser
        self.isFetchingContent = isFetchingContent
        self.onPreviousArticle = onPreviousArticle
        self.onNextArticle = onNextArticle
        self.canSelectPrevious = canSelectPrevious
        self.canSelectNext = canSelectNext
    }

    private var articleText: String {
        guard let item else { return "Pick a story from the list to read it here." }
        return item.articleBody.isEmpty ? "No article content is available yet." : item.articleBody
    }

    /// The full HTML document handed to the reading-pane web view: the
    /// article fragment (feed HTML or the page fetched from the link) with
    /// relative URLs resolved, wrapped in reading-pane typography.
    ///
    /// URL resolution runs regex passes over the whole article, so the
    /// resolved body is cached per article — the font-size slider and other
    /// pane re-renders only pay for the (cheap) template rebuild.
    private static var bodyCache: [String: String] = [:]
    private static var bodyCacheOrder: [String] = []
    private static let bodyCacheLock = NSLock()
    private static let bodyCacheLimit = 8

    private var articleDocument: String {
        guard let item else {
            return Self.document(body: "<p>Pick a story from the list to read it here.</p>", fontSize: readingFontSize, scheme: colorScheme)
        }

        let cacheKey = "\(item.id.uuidString)|\(item.rawArticleHTML.hashValue)"
        Self.bodyCacheLock.lock()
        let cached = Self.bodyCache[cacheKey]
        Self.bodyCacheLock.unlock()

        let bodyHTML: String
        if let cached {
            bodyHTML = cached
        } else {
            if item.contentHTML.isEmpty {
                // Only plain text is known (fetch failed / no link yet) —
                // render it as paragraphs instead of dumping raw text.
                bodyHTML = Self.plainTextParagraphs(from: item.rawArticleHTML)
            } else if let base = item.link.flatMap(URL.init(string:)) {
                // Feed HTML can carry relative image paths — resolve them so
                // pictures render inside the app.
                bodyHTML = ArticleContentLoader.resolveURLs(in: item.rawArticleHTML, base: base)
            } else {
                bodyHTML = item.rawArticleHTML
            }

            Self.bodyCacheLock.lock()
            Self.bodyCache[cacheKey] = bodyHTML
            Self.bodyCacheOrder.append(cacheKey)
            if Self.bodyCacheOrder.count > Self.bodyCacheLimit {
                Self.bodyCache[Self.bodyCacheOrder.removeFirst()] = nil
            }
            Self.bodyCacheLock.unlock()
        }

        return Self.document(body: bodyHTML, fontSize: readingFontSize, scheme: colorScheme)
    }

    private var summaryText: String {
        guard let item else { return "Pick a story to inspect it here." }
        return summaryOverride ?? "No summary generated yet. Select an article to auto-generate."
    }

    var body: some View {
        ScrollViewReader { proxy in
            pane(proxy)
        }
    }

    /// The scrollable pane content. Split out so the wrapper above can own
    /// the scroll-reset proxy without disturbing this layout.
    private func pane(_ proxy: ScrollViewProxy) -> some View {
        ScrollView {
            // Lazy so full-window layout passes don't re-measure the entire
            // article body below the fold on every invalidation.
            LazyVStack(alignment: .leading, spacing: 0) {
                // Scroll anchor — selecting another article returns the pane
                // to the top instead of inheriting the previous offset.
                Color.clear.frame(height: 0).id(Self.topAnchorID)
                // Feed-wide 12-hour summary — always shown at top
                if let feedWideSummary, !feedWideSummary.isEmpty {
                    VStack(alignment: .leading, spacing: PrecisSpacing.sm) {
if isGeneratingSummary {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .tint(PrecisDesignSystem.marginalia)
                            .padding(.bottom, PrecisSpacing.sm)
                    }

                    HStack {
                        Image(systemName: "clock.badge.checkmark")
                            .foregroundStyle(PrecisDesignSystem.marginalia)
                        Text("Today's Digest")
                            .font(PrecisTypography.headline)
                            .foregroundStyle(PrecisDesignSystem.marginalia)
                        Spacer()
                        }

                        Text(feedWideSummary)
                            .font(.system(size: readingFontSize))
                            .lineSpacing(5)
                            .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.85))
                    }
                    .padding(PrecisSpacing.md)
                    .background(PrecisDesignSystem.marginalia.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.bottom, PrecisSpacing.lg)
                }

                HStack(alignment: .top) {
                    Text(item?.title ?? "Select an article")
                        // Same typeface as the article-list titles in the
                        // window's top section.
                        .font(PrecisTypography.headline)
                        .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))
                        .padding(.bottom, PrecisSpacing.sm)

                    Spacer()

                    if let item, let onOpenInBrowser {
                        HStack(spacing: 8) {
                            Button(action: { onOpenInBrowser() }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "safari")
                                        .font(.caption)
                                    Text("Open in Browser")
                                        .font(PrecisTypography.metadata)
                                }
                            }
                            .buttonStyle(.bordered)

                            Button(action: { onGenerateSummary?() }) {
                                HStack(spacing: 6) {
                                    Text(isGeneratingSummary ? "Generating…" : "Generate summary")
                                        .font(PrecisTypography.metadata)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isGeneratingSummary)
                        }
                    }

                    if onPreviousArticle != nil, onNextArticle != nil {
                        articleNavigationControl
                    }
                }

                HStack(spacing: PrecisSpacing.sm) {
                    Text(item.map { FeedDiscoveryService.conciseTitle($0.feedTitle) } ?? "Inbox")
                        .font(PrecisTypography.metadata)
                        .foregroundStyle(PrecisDesignSystem.marginalia)

                    if let item, showReadingTime {
                        Text("•")
                            .foregroundStyle(Color.accentColor)

                        Text("\(item.readingTimeMinutes) min read")
                            .font(PrecisTypography.metadata)
                            .foregroundStyle(PrecisDesignSystem.marginalia)

                        Text("•")
                            .foregroundStyle(Color.accentColor)
                    } else if item == nil {
                        Text("•")
                            .foregroundStyle(Color.accentColor)
                    }

                    Text(item?.publishedDate.map { relativeDateString(from: $0) } ?? "No date")
                        .font(PrecisTypography.metadata)
                        .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.7))
                }
                .padding(.bottom, PrecisSpacing.md)

                VStack(alignment: .leading, spacing: PrecisSpacing.md) {
                    if item != nil {
                        VStack(alignment: .leading, spacing: PrecisSpacing.xs) {
                            Text("Summary")
                                .font(PrecisTypography.caption)
                                .foregroundStyle(PrecisDesignSystem.marginalia)
                                .textCase(.uppercase)
                                .tracking(1.2)

                            Text(summaryText)
                                .font(.system(size: readingFontSize))
                                .lineSpacing(7)
                                .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.85))
                        }
                    }

                    if isFetchingContent {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading full article…")
                                .font(PrecisTypography.metadata)
                                .foregroundStyle(PrecisDesignSystem.marginalia)
                        }
                        .padding(.bottom, PrecisSpacing.xs)
                    }

                    // Full article as a formatted document — headings, links
                    // and images render natively, and it re-renders whenever
                    // a font-size change rewrites `articleDocument`.
                    ArticleHTMLView(
                        document: articleDocument,
                        baseURL: item?.link.flatMap(URL.init(string:)),
                        onHeightChange: { articleHeight = $0 }
                    )
                    .frame(height: max(articleHeight, 1))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(PrecisSpacing.xl)
        }
        .onChange(of: item?.id) { _, _ in
            // A new article starts at the top with a fresh height — the old
            // scroll offset and web-view height otherwise left a blank
            // region around the new, shorter content.
            articleHeight = 320
            proxy.scrollTo(Self.topAnchorID, anchor: .top)
        }
    }

    // MARK: - Article step controls

    /// Safari-style `‹ | ›` segment at the pane's top right — steps the
    /// selection to the article above/below the current one.
    private var articleNavigationControl: some View {
        HStack(spacing: 0) {
            Button(action: { onPreviousArticle?() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(!canSelectPrevious)
            .opacity(canSelectPrevious ? 1 : 0.35)
            .help("Previous article")

            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1, height: 14)

            Button(action: { onNextArticle?() }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(!canSelectNext)
            .opacity(canSelectNext ? 1 : 0.35)
            .help("Next article")
        }
        .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.75))
        .padding(.horizontal, 4)
        .background(
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            Capsule()
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func relativeDateString(from date: Date) -> String {
        let delta = Int(Date().timeIntervalSince(date))
        if delta < 60 { return "now" }
        if delta < 3600 { return "\(delta / 60) minutes ago" }
        if delta < 86400 { return "\(delta / 3600) hours ago" }
        return "\(delta / 86400) days ago"
    }

    // MARK: - Article document

    /// Wraps the article fragment in a full HTML document styled with the
    /// design system's colors and the user's reading font size.
    private static func document(body: String, fontSize: Double, scheme: ColorScheme) -> String {
        let foreground = css(PrecisDesignSystem.foreground(for: scheme))
        let background = css(PrecisDesignSystem.background(for: scheme))
        let muted = css(PrecisDesignSystem.foreground(for: scheme), opacity: 0.62)
        let surface = css(PrecisDesignSystem.surface(for: scheme))
        let rule = css(PrecisDesignSystem.rule(for: scheme))
        let marginalia = css(PrecisDesignSystem.marginalia)
        let accent = css(Color(nsColor: NSColor.controlAccentColor))

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        html, body { margin: 0; padding: 0; background: \(background); }
        body {
            padding: 0 2px 8px;
            color: \(foreground);
            background: \(background);
            font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
            font-size: \(Int(fontSize))px;
            line-height: 1.65;
            word-wrap: break-word;
            overflow-wrap: break-word;
        }
        p { margin: 0 0 1.05em; }
        a { color: \(accent); text-decoration: none; }
        a:hover { text-decoration: underline; }
        img, video { display: block; max-width: 100%; height: auto; margin: 1.2em auto; border-radius: 8px; }
        figure { margin: 1.2em 0; }
        figcaption { margin-top: .5em; font-size: .85em; color: \(muted); text-align: center; }
        h1, h2, h3, h4, h5 { font-weight: 600; line-height: 1.25; margin: 1.5em 0 .55em; color: \(foreground); }
        h1 { font-size: 1.55em; }
        h2 { font-size: 1.3em; }
        h3 { font-size: 1.12em; }
        h4, h5 { font-size: 1em; }
        ul, ol { margin: 0 0 1.05em; padding-left: 1.5em; }
        li { margin: .3em 0; }
        blockquote { margin: 1.2em 0; padding: .3em 0 .3em 1em; border-left: 3px solid \(marginalia); color: \(muted); font-style: italic; }
        pre { margin: 1.2em 0; padding: 12px 14px; background: \(surface); border-radius: 8px; overflow-x: auto; font-size: .88em; line-height: 1.5; }
        code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .9em; background: \(surface); padding: 1px 5px; border-radius: 4px; }
        pre code { padding: 0; background: transparent; }
        hr { border: none; border-top: 1px solid \(rule); margin: 1.8em 0; }
        table { width: 100%; border-collapse: collapse; margin: 1.2em 0; font-size: .92em; }
        th, td { border: 1px solid \(rule); padding: 6px 9px; text-align: left; }
        th { background: \(surface); font-weight: 600; }
        del { color: \(muted); }
        </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }

    /// Escapes plain text and lays it out as paragraphs — the fallback when
    /// no HTML has been stored for an article yet.
    private static func plainTextParagraphs(from text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let paragraphs = escaped
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !paragraphs.isEmpty else {
            return "<p>No article content is available yet.</p>"
        }
        return paragraphs.map { "<p>\($0)</p>" }.joined()
    }

    /// Design-system color → CSS `rgba()` so the document matches the pane.
    private static func css(_ color: Color, opacity: Double = 1) -> String {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .black
        let red = Int((nsColor.redComponent * 255).rounded())
        let green = Int((nsColor.greenComponent * 255).rounded())
        let blue = Int((nsColor.blueComponent * 255).rounded())
        return "rgba(\(red), \(green), \(blue), \(String(format: "%.2f", opacity)))"
    }
}

private struct SummaryColumn: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: PrecisSpacing.sm) {
            Text("MARGINALIA")
                .font(PrecisTypography.caption)
                .foregroundStyle(PrecisDesignSystem.marginalia)
                .tracking(1.2)

            Divider()
                .background(PrecisDesignSystem.rule(for: colorScheme))

            Text(text)
                .font(PrecisTypography.body)
                .foregroundStyle(PrecisDesignSystem.marginalia)
                .lineSpacing(5)

            Text("- calmer reading\n- less clutter\n- more attention")
                .font(PrecisTypography.metadata)
                .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.8))
                .lineSpacing(4)
        }
        .padding(PrecisSpacing.md)
        .background(PrecisDesignSystem.surface(for: colorScheme))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(PrecisDesignSystem.rule(for: colorScheme), lineWidth: 1)
        )
    }
}

/// The article web view never scrolls itself — it is sized to its content,
/// so WebKit's internal scroller has nothing to do but still swallows mouse-
/// wheel/trackpad events, leaving the pane's scroll bar draggable but the
/// wheel dead. Hand every wheel event to the enclosing scroll view instead.
private final class ArticlePaneWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        if let enclosingScrollView {
            enclosingScrollView.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

/// Renders a formatted HTML document at its natural content height so it can
/// sit inside the reading pane's `ScrollView`: a injected script reports
/// `body` height (including images as they load) back to SwiftUI, and link
/// taps open in the default browser instead of navigating the pane away.
struct ArticleHTMLView: NSViewRepresentable {
    let document: String
    let baseURL: URL?
    let onHeightChange: (CGFloat) -> Void

    init(document: String, baseURL: URL? = nil, onHeightChange: @escaping (CGFloat) -> Void) {
        self.document = document
        self.baseURL = baseURL
        self.onHeightChange = onHeightChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onHeightChange: onHeightChange)
    }

    func makeNSView(context: Context) -> WKWebView {
        let userController = WKUserContentController()
        userController.add(context.coordinator, name: "precisArticleHeight")
        userController.addUserScript(
            WKUserScript(source: Self.heightReporter, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userController

        let webView = ArticlePaneWebView(frame: .zero, configuration: configuration)
        webView.underPageBackgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        context.coordinator.lastDocument = document
        context.coordinator.lastBaseURL = baseURL
        context.coordinator.currentNavigation = webView.loadHTMLString(document, baseURL: baseURL)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onHeightChange = onHeightChange
        guard context.coordinator.lastDocument != document else { return }
        context.coordinator.lastDocument = document
        context.coordinator.lastBaseURL = baseURL
        context.coordinator.currentNavigation = webView.loadHTMLString(document, baseURL: baseURL)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "precisArticleHeight")
    }

    private static let heightReporter = """
    (function() {
        function post() {
            try {
                var h = Math.ceil(Math.max(
                    document.body.scrollHeight,
                    document.documentElement.scrollHeight
                ));
                window.webkit.messageHandlers.precisArticleHeight.postMessage(h);
            } catch (e) {}
        }
        window.addEventListener('load', post);
        document.addEventListener('DOMContentLoaded', post);
        window.addEventListener('resize', post);
        if (window.ResizeObserver) {
            new ResizeObserver(post).observe(document.documentElement);
        }
        post();
    })();
    """

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var lastDocument: String?
        var lastBaseURL: URL?
        /// The navigation our own `loadHTMLString` started — failures are
        /// only retried when THEY belong to it, never for sub-frame embeds.
        var currentNavigation: WKNavigation?
        /// Failed loads retry this many times before giving up, so a
        /// crash-looping page can't spin the web view forever. Rearmed by
        /// every successful load.
        var loadAttempts = 0
        var onHeightChange: (CGFloat) -> Void

        init(onHeightChange: @escaping (CGFloat) -> Void) {
            self.onHeightChange = onHeightChange
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "precisArticleHeight", let height = message.body as? Double else { return }
            onHeightChange(CGFloat(height))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // A clean load re-arms failure retries for this document.
            loadAttempts = 0
            // Belt and braces for the injected reporter: measure once more
            // after the document settles.
            webView.evaluateJavaScript("Math.ceil(document.body.scrollHeight)") { [weak self] result, _ in
                if let height = result as? Double {
                    self?.onHeightChange(CGFloat(height))
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            reloadAfterFailure(webView, navigation: navigation, error: error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            reloadAfterFailure(webView, navigation: navigation, error: error)
        }

        /// The WebContent process was killed (memory pressure after a long
        /// session) — without a reload the pane stayed blank until the app
        /// was restarted.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            retryLoad(webView)
        }

        /// A failed main-frame load used to leave `lastDocument` claiming the
        /// pane was current, so every later `updateNSView` skipped the reload
        /// and the blank web view never recovered. Retry a couple of times —
        /// a fresh `loadHTMLString` also revives a killed render process.
        private func reloadAfterFailure(_ webView: WKWebView, navigation: WKNavigation!, error: Error) {
            // Only the document load WE issued — a failing sub-frame embed
            // must not reset the article. With no recorded navigation (e.g.
            // the load never started) fall through and let the retry help.
            if let current = currentNavigation, let navigation, navigation !== current { return }
            let nsError = error as NSError
            // Loads superseded by a newer click and links cancelled by the
            // policy handler are not failures.
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
            if nsError.domain == "WebKitErrorDomain", nsError.code == 102 { return }
            retryLoad(webView)
        }

        private func retryLoad(_ webView: WKWebView) {
            guard loadAttempts < 2, let document = lastDocument else { return }
            loadAttempts += 1
            currentNavigation = webView.loadHTMLString(document, baseURL: lastBaseURL)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // In-article links leave the app for the default browser; the
            // web view itself only ever renders the article document.
            if navigationAction.targetFrame?.isMainFrame == true,
               let url = navigationAction.request.url,
               let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

#Preview {
    ReadingPaneView(item: ArticleListItem(
        title: "The quiet power of good reading interfaces",
        feedTitle: "The Verge",
        publishedDate: Date().addingTimeInterval(-180),
        isRead: false,
        isStarred: true,
        snippet: "Quiet interfaces don’t subtract from the reading experience — they make it easier to trust the words in front of you."
    ))
}

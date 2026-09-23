import SwiftUI

struct ReadingPaneView: View {
    let item: ArticleListItem?
    let summaryOverride: String?
    let feedWideSummary: String?
    let isGeneratingSummary: Bool
    let onGenerateSummary: (() -> Void)?
    let onOpenInBrowser: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    init(
        item: ArticleListItem?,
        summaryOverride: String? = nil,
        feedWideSummary: String? = nil,
        isGeneratingSummary: Bool = false,
        onGenerateSummary: (() -> Void)? = nil,
        onOpenInBrowser: (() -> Void)? = nil
    ) {
        self.item = item
        self.summaryOverride = summaryOverride
        self.feedWideSummary = feedWideSummary
        self.isGeneratingSummary = isGeneratingSummary
        self.onGenerateSummary = onGenerateSummary
        self.onOpenInBrowser = onOpenInBrowser
    }

    private var articleText: String {
        guard let item else { return "Pick a story from the list to read it here." }
        return item.articleBody.isEmpty ? "No article content is available yet." : item.articleBody
    }

    private var articleAttributedText: AttributedString {
        guard let item else {
            return AttributedString("Pick a story from the list to read it here.")
        }
        let raw = item.rawArticleHTML
        if raw.isEmpty {
            return AttributedString("No article content is available yet.")
        }
        return HTMLAttributedStringRenderer.render(raw)
    }

    private var summaryText: String {
        guard let item else { return "Pick a story to inspect it here." }
        return summaryOverride ?? "No summary generated yet. Select an article to auto-generate."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
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
                            .font(PrecisTypography.body)
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
                        .font(PrecisTypography.title)
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
                }

                HStack(spacing: PrecisSpacing.sm) {
                    Text(item?.feedTitle ?? "Inbox")
                        .font(PrecisTypography.metadata)
                        .foregroundStyle(PrecisDesignSystem.marginalia)

                    Text("•")
                        .foregroundStyle(PrecisDesignSystem.rule(for: colorScheme))

                    if let item {
                        Text("\(item.readingTimeMinutes) min read")
                            .font(PrecisTypography.metadata)
                            .foregroundStyle(PrecisDesignSystem.marginalia)

                        Text("•")
                            .foregroundStyle(PrecisDesignSystem.rule(for: colorScheme))
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
                                .font(PrecisTypography.body)
                                .lineSpacing(7)
                                .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.85))
                        }
                    }

                    Text(articleAttributedText)
                        .font(PrecisTypography.body)
                        .lineSpacing(7)
                        .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(PrecisSpacing.xl)
        }
    }

    private func relativeDateString(from date: Date) -> String {
        let delta = Int(Date().timeIntervalSince(date))
        if delta < 60 { return "just now" }
        if delta < 3600 { return "\(delta / 60) minutes ago" }
        if delta < 86400 { return "\(delta / 3600) hours ago" }
        return "\(delta / 86400) days ago"
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

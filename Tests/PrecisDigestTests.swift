import SwiftData
import XCTest
@testable import Precis

final class PrecisDigestTests: XCTestCase {
    // MARK: - Card composition

    /// The bug this guards: the card printed its own paragraph a second time as
    /// a bullet, so "Today's Precis" read as two copies of the same summary.
    func testCardTextDropsBulletsThatRepeatTheParagraph() {
        let paragraph = "Apple killed the last remaining R2-D2 unit on display."
        let card = PrecisDigest.cardText(
            articleCount: 25,
            paragraph: paragraph,
            bullets: [paragraph, "Apple shipped a smaller Mac mini.", paragraph.lowercased()]
        )

        XCTAssertTrue(card.hasPrefix("**25 articles from the last 24 hours:**"))
        XCTAssertEqual(card.components(separatedBy: paragraph).count - 1, 1, card)
        XCTAssertEqual(bulletLines(in: card), ["• Apple shipped a smaller Mac mini."])
    }

    /// Authored markers must not survive: views add the glyph themselves, and
    /// two of them rendered as "• • Headline".
    func testCardTextStripsAuthoredBulletMarkers() {
        let card = PrecisDigest.cardText(
            articleCount: 2,
            paragraph: "",
            bullets: ["• • Headline one", "- Headline two"]
        )

        XCTAssertEqual(bulletLines(in: card), ["• Headline one", "• Headline two"])
    }

    func testCardTextOmitsEmptyParagraphAndEmptyBullets() {
        let card = PrecisDigest.cardText(articleCount: 3, paragraph: "   \n", bullets: ["", "Headline"])

        XCTAssertEqual(card, "**3 articles from the last 24 hours:**\n\n• Headline")
    }

    func testStripBulletMarkersRemovesDoubledGlyphs() {
        XCTAssertEqual(HeuristicSummarization.stripBulletMarkers("• • Headline"), "Headline")
        XCTAssertEqual(HeuristicSummarization.stripBulletMarkers(" -  Headline "), "Headline")
        XCTAssertEqual(HeuristicSummarization.stripBulletMarkers("Headline"), "Headline")
    }

    // MARK: - Heuristic fallback

    func testHeuristicDigestKeepsParagraphAndBulletsDisjoint() {
        let summary = HeuristicSummarization.summarizeDigest(digestInput(lines: 12))
        let card = PrecisDigest.cardText(
            articleCount: 12,
            paragraph: summary.shortText,
            bullets: summary.bulletPoints
        )

        XCTAssertFalse(summary.shortText.isEmpty)
        XCTAssertFalse(summary.bulletPoints.isEmpty)
        XCTAssertEqual(Set(summary.bulletPoints).count, summary.bulletPoints.count)
        for bullet in summary.bulletPoints {
            XCTAssertFalse(
                summary.shortText.localizedCaseInsensitiveContains(bullet),
                "The paragraph states the bullet again: \(bullet)"
            )
        }
        XCTAssertFalse(card.contains("• •"), card)
        XCTAssertEqual(card.components(separatedBy: summary.shortText).count - 1, 1, card)
    }

    func testHeuristicDigestUsesASingleArticleOnlyOnce() {
        let summary = HeuristicSummarization.summarizeDigest(digestInput(lines: 1))

        XCTAssertFalse(summary.shortText.isEmpty)
        XCTAssertTrue(summary.bulletPoints.isEmpty, "One article cannot fill both a paragraph and bullets")
    }

    /// Article summaries fed both their paragraph and their bullets from the
    /// same sentences, which printed the opening of every article twice.
    func testHeuristicArticleSummaryDoesNotRepeatItsParagraph() {
        let text = """
        First sentence about the topic at hand. Second sentence with more detail \
        about it. Third sentence that adds a further fact.
        """

        let summary = HeuristicSummarization.summarize(text)

        XCTAssertEqual(
            summary.shortText,
            "First sentence about the topic at hand. Second sentence with more detail about it."
        )
        XCTAssertEqual(summary.bulletPoints, ["Third sentence that adds a further fact."])
    }

    func testSentencesKeepTheirTerminators() {
        let sentences = HeuristicSummarization.sentences(
            from: "A first sentence of some length here. A second one that is long enough too."
        )

        XCTAssertEqual(
            sentences,
            ["A first sentence of some length here.", "A second one that is long enough too."]
        )
    }

    // MARK: - End to end

    /// The reported bug, through the real view model: "Today's Precis" read as
    /// the same summary twice, and it had to cover the last 24 hours.
    @MainActor
    func testFeedWideSummaryCoversTheLast24HoursWithoutRepeating() async throws {
        let container = try ModelContainer(
            for: ModelContainerProvider.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let now = Date()

        for index in 1...3 {
            context.insert(
                ArticleRecord(
                    title: "Recent story \(index)",
                    publishedDate: now.addingTimeInterval(-Double(index) * 3600),
                    extractedContent: "Recent story \(index) broke today and this sentence explains what happened in it."
                )
            )
        }
        context.insert(
            ArticleRecord(
                title: "Yesterday's news",
                publishedDate: now.addingTimeInterval(-30 * 3600),
                extractedContent: "Old news that is well outside the window and must stay out of the digest here."
            )
        )
        try context.save()

        let viewModel = ArticleListViewModel()
        await viewModel.generateFeedWideSummary(context: context)

        let text = viewModel.feedWideSummaryText
        XCTAssertTrue(text.hasPrefix("**3 articles from the last 24 hours:**"), text)
        XCTAssertFalse(text.contains("Yesterday's news"), text)
        XCTAssertFalse(text.contains("• •"), text)

        let bullets = bulletLines(in: text)
        XCTAssertEqual(Set(bullets).count, bullets.count, text)

        let paragraph = text
            .components(separatedBy: "\n\n")
            .first { !$0.hasPrefix("**") && !$0.hasPrefix("• ") } ?? ""
        for bullet in bullets {
            XCTAssertFalse(
                paragraph.localizedCaseInsensitiveContains(String(bullet.dropFirst(2))),
                "The paragraph states the bullet again:\n\(text)"
            )
        }
    }

    // MARK: - Live provider

    /// Runs the provider the app picks, so the on-device path is covered as
    /// well; skipped on machines where Apple Intelligence is switched off.
    func testLiveDigestCardDoesNotRepeatItself() async throws {
        let provider = SummarizationProviderFactory.makeDefault()
        try XCTSkipUnless(provider.availability(), "No on-device model on this machine")

        let summary = try await provider.summarizeDigest(digestInput(lines: 6))
        let card = PrecisDigest.cardText(
            articleCount: 6,
            paragraph: summary.shortText,
            bullets: summary.bulletPoints
        )
        let bullets = bulletLines(in: card)

        XCTAssertFalse(summary.shortText.isEmpty)
        XCTAssertTrue(card.contains(summary.shortText), card)
        XCTAssertEqual(Set(bullets).count, bullets.count, "The card repeats a takeaway:\n\(card)")
        XCTAssertLessThanOrEqual(bullets.count, summary.bulletPoints.count)
        for bullet in bullets {
            let takeaway = String(bullet.dropFirst(2))
            XCTAssertFalse(
                summary.shortText.localizedCaseInsensitiveContains(takeaway),
                "The paragraph states the takeaway again: \(takeaway)"
            )
        }
    }

    // MARK: - Helpers

    private func digestInput(lines: Int) -> String {
        (1...lines)
            .map { "• Headline \($0): Story \($0) broke today and this sentence says what happened." }
            .joined(separator: "\n\n")
    }

    private func bulletLines(in card: String) -> [String] {
        card
            .components(separatedBy: .newlines)
            .filter { $0.hasPrefix("• ") }
    }
}

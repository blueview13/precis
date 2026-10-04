import XCTest
@testable import Precis

/// Fixtures mirror the reported cluttered article: source-site metadata
/// (category, timestamp, byline, read-time, hashtags, location, share row)
/// and a repeated headline, ahead of the real body.
final class ArticleHTMLSanitizerTests: XCTestCase {
    private let title = "City's 'Irrefutable Evidence' Revealed as Appeal Looms"

    private let clutteredFixture = """
    <p>Latest News</p>
    <p>2 October 2026 18:02 •</p>
    <p>Peter Swales</p>
    <p>• 3 min read</p>
    <p>Manchester City's plan to clear their name has been revealed, with the club \
    set to confirm their appeal against the independent commission's verdict immediately.</p>
    <p><a href="https://example.com/tag/premier">#Premier League</a> \
    <a href="https://example.com/tag/squad">#Squad News</a> \
    <a href="https://example.com/tag/analysis">#Analysis</a></p>
    <p>Etihad Stadium</p>
    <p><a href="https://twitter.com/intent/tweet">Share on X</a> \
    <a href="https://facebook.com/sharer">Share on Facebook</a></p>
    <h1>City's 'Irrefutable Evidence' Revealed as Appeal Looms</h1>
    <p>Manchester City's plan to clear their name has been laid out in a new report, \
    with the club set to confirm their appeal against the independent commission's \
    verdict imminent.</p>
    <p>The independent commission had ruled that the payments were sham contracts \
    that saw over £900 million illegally pumped into the club's accounts, a finding \
    the club has always maintained is wrong and should be overturned on appeal.</p>
    <p>Keegan also reports that City's legal team will question the length of time \
    the panel took to deliver its verdict after the hearing concluded last season.</p>
    """

    private func sanitized(_ html: String, title: String? = nil) -> String {
        ArticleHTMLSanitizer.sanitize(html, title: title ?? self.title)
    }

    // MARK: - Chrome removal

    func testStripsLeadingMetadataRegion() {
        let result = sanitized(clutteredFixture)

        XCTAssertFalse(result.contains("Latest News"), "category label should be removed")
        XCTAssertFalse(result.contains("2 October 2026"), "timestamp should be removed")
        XCTAssertFalse(result.contains("Peter Swales"), "byline should be removed")
        XCTAssertFalse(result.contains("min read"), "read-time estimate should be removed")
        XCTAssertFalse(result.contains("Etihad Stadium"), "location should be removed")
        XCTAssertFalse(result.contains("#Premier League"), "hashtags should be removed")
        XCTAssertFalse(result.contains("Share on X"), "share links should be removed")
    }

    func testKeepsBodyIntact() {
        let result = sanitized(clutteredFixture)

        XCTAssertTrue(result.contains("has been laid out in a new report"))
        XCTAssertTrue(result.contains("sham contracts"))
        XCTAssertTrue(result.contains("legal team will question"))
    }

    func testRemovesHeadlineRepeatingThePaneTitle() {
        let result = sanitized(clutteredFixture)
        let h1Count = result.components(separatedBy: "<h1").count - 1
        XCTAssertEqual(h1Count, 0, "the pane already renders the title above the body")
    }

    func testKeepsMidContentHeadlineThatDiffersFromTitle() {
        let fragment = """
        <p>A substantial opening paragraph that clearly qualifies as body content \
        because it runs well past the minimum length threshold for these checks here.</p>
        <h1>Something Else Entirely</h1>
        <p>Closing paragraph of the fragment with enough characters to qualify as \
        real body content rather than metadata of any recognizable sort.</p>
        """
        let result = sanitized(fragment)
        XCTAssertTrue(result.contains("<h1>Something Else Entirely</h1>"))
    }

    // MARK: - Deck handling

    func testRemovesDeckParaphrasingFirstBodyParagraph() {
        let result = sanitized(clutteredFixture)
        XCTAssertFalse(
            result.contains("has been revealed, with the club set to confirm"),
            "a deck that restates the body should be dropped"
        )
    }

    func testKeepsGenuineSubhead() {
        let fragment = """
        <p>Category</p>
        <h2>City's spending spread far beyond the Premier League</h2>
        <p>Manchester City's transfer dealings between 2009/10 and 2017/18 went \
        through 46 selling clubs in 19 different national league systems, according \
        to a new analysis of the research put together by journalists this week.</p>
        """
        let result = sanitized(fragment)
        XCTAssertTrue(result.contains("City's spending spread far beyond the Premier League"))
        XCTAssertFalse(result.contains(">Category<"))
    }

    // MARK: - Site-header + hero image regression (not-really-here feed)

    private let siteHeaderFixture = """
    <article class="lg:col-span-3"> <div class="bg-white rounded-lg shadow-sm p-6">
    <header class="mb-6"> <div class="mb-4"> \
    <a href="https://example.com/category/latest-news" class="inline-block px-1.5 text-white uppercase"> \
    Latest News </a> </div> <div class="flex flex-wrap items-center text-sm"> \
    <time datetime="2026-10-04T06:30:31.94+00:00"> 4 October 2026   07:30 </time> \
    <img src="https://example.com/uploads/avatar.png" alt="Peter Swales" class="w-6 h-6 rounded-full"> \
    Peter Swales </div> </header> \
    <div class="mb-8" itemprop="image" itemscope itemtype="https://schema.org/ImageObject"> \
    <img src="https://example.com/uploads/hero.webp" alt="Nico O'Reilly in action for Manchester City." \
    class="w-full h-auto rounded-lg" width="1200" height="630"> \
    <p class="text-sm italic" itemprop="caption"> Nico O'Reilly </p> </div> \
    <div class="mb-8 post-content" itemprop="articleBody"> <p>Manchester City's plan to clear \
    their name has been laid out in a new report, with the club set to confirm their appeal \
    against the independent commission's verdict imminent.</p> <p>Closing body paragraph that \
    rounds out the fragment with enough text to be unambiguously real content here.</p> </div> \
    </article>
    """

    func testSiteHeaderDropsButHeroImageSurvives() {
        let result = sanitized(siteHeaderFixture)
        XCTAssertFalse(result.contains("Latest News"), "category badge is chrome")
        XCTAssertFalse(result.contains("4 October 2026"), "publish date is chrome")
        XCTAssertFalse(result.contains("Peter Swales"), "byline is chrome")
        XCTAssertTrue(result.contains("hero.webp"), "the hero image must survive")
        XCTAssertTrue(result.contains("caption"), "the image caption rides along")
        XCTAssertTrue(result.contains("verdict imminent"), "body text survives")
    }

    func testHeroImageSurvivesWithControlBytePrefix() {
        // Stored articles carry a 0x01 storage marker before the markup.
        let result = sanitized("\u{01}" + siteHeaderFixture)
        XCTAssertTrue(result.contains("hero.webp"), "storage marker must not stall the strip")
        XCTAssertFalse(result.contains("Latest News"), "chrome still drops with the marker present")
    }

    func testArticleMentioningADateIsNotTreatedAsChrome() {
        // The <article> element's concatenated text contains dates; the
        // date-chrome check must only apply to short headings.
        let result = sanitized(siteHeaderFixture)
        XCTAssertTrue(result.contains("<article"), "the article wrapper itself is never chrome")
    }

    // MARK: - Wrapper descent

    func testDescendsIntoWrapperElement() {
        let fragment = """
        <div class="post-body">
        <span>Latest News</span>
        <span>2 October 2026 18:02</span>
        <p>A proper body paragraph that is long enough to be recognized as the \
        start of real article content rather than a metadata label of some kind.</p>
        </div>
        """
        let result = sanitized(fragment)
        XCTAssertTrue(result.contains("<div class=\"post-body\">"), "wrapper tag is preserved")
        XCTAssertTrue(result.contains("proper body paragraph"))
        XCTAssertFalse(result.contains("Latest News"))
        XCTAssertFalse(result.contains("2 October 2026"))
        XCTAssertTrue(result.contains("</div>"), "wrapper close tag is preserved")
    }

    // MARK: - Safety properties

    func testReturnsOriginalWhenSanitizingWouldBlankTheArticle() {
        // A fragment that is nearly all short metadata-looking lines — the
        // retention check must reject the pass and return it untouched.
        let fragment = "<p>Latest News</p><p>Peter Swales</p><p>Etihad Stadium</p>"
        let result = sanitized(fragment)
        XCTAssertEqual(result, fragment)
    }

    func testNeverDropsMediaOnlyNode() {
        let fragment = """
        <p><img src="/lead.jpg" alt="Lead image"></p>
        <p>Body paragraph long enough to be recognized as content rather than \
        a label, with sufficient characters to cross the metadata thresholds.</p>
        """
        let result = sanitized(fragment)
        XCTAssertTrue(result.contains("<img"), "a lead image is content, not chrome")
    }

    func testEmptyFragmentAndNilTitleAreSafe() {
        XCTAssertEqual(ArticleHTMLSanitizer.sanitize("", title: title), "")
        let result = ArticleHTMLSanitizer.sanitize(clutteredFixture, title: nil)
        XCTAssertFalse(result.contains("Share on X"))
        XCTAssertTrue(result.contains("sham contracts"))
    }

    // MARK: - Plain-text fallback

    func testPlainTextDropsMetadataLinesAndKeepsBody() {
        let text = """
        Latest News
        2 October 2026 18:02
        Peter Swales
        • 3 min read
        A long body paragraph that survives because it is not a short metadata \
        label and carries none of the patterns the line filter looks for at all.
        Share on X
        """
        let result = ArticleHTMLSanitizer.sanitizePlainText(text, title: nil)
        XCTAssertFalse(result.contains("Latest News"))
        XCTAssertFalse(result.contains("Peter Swales"))
        XCTAssertFalse(result.contains("min read"))
        XCTAssertFalse(result.contains("Share on X"))
        XCTAssertTrue(result.contains("long body paragraph"))
    }

    func testPlainTextDropsLeadingLineRepeatingTitle() {
        let body = "Body of the article that follows the duplicated headline "
            + "line and is long enough to never be mistaken for a metadata label here."
        let text = "\(title)\n\(body)"
        let result = ArticleHTMLSanitizer.sanitizePlainText(text, title: title)
        XCTAssertFalse(result.contains("Irrefutable Evidence"))
        XCTAssertTrue(result.contains("Body of the article"))
    }

    // MARK: - Ad images

    func testRemovesAdBannerImage() {
        let html = """
        <p>Real body text long enough to survive the retention check comfortably.</p>
        <img src="https://ads.example.com/banner/300x250.jpg" alt="Advertisement">
        <p>More real body text that keeps the article from being rejected.</p>
        """
        let result = sanitized(html)
        XCTAssertFalse(result.contains("300x250"))
        XCTAssertTrue(result.contains("Real body text"))
    }

    func testRemovesTrackingPixelButKeepsEditorialPhoto() {
        let html = """
        <p>Story text that is long enough to survive the sanitizer's retention check.</p>
        <img src="https://example.com/photo.jpg" alt="A real photo">
        <img src="https://tracker.example.com/p.gif" width="1" height="1">
        <p>Trailing paragraph so plenty of visible text remains after sanitizing.</p>
        """
        let result = sanitized(html)
        XCTAssertTrue(result.contains("photo.jpg"))
        XCTAssertFalse(result.contains("p.gif"))
    }

    // MARK: - Entity decoding

    func testPlainTextDecodesNumericAndNamedEntities() {
        let html = "<p>John Ternus&#8217;s &#8216;hands-on&#8217; role &amp; more&hellip;</p>"
        let result = ArticleHTMLSanitizer.plainText(fromHTML: html)
        XCTAssertFalse(result.contains("&#"))
        XCTAssertFalse(result.contains("&hellip;"))
        XCTAssertTrue(result.contains("John Ternus’s ‘hands-on’ role & more…"))
    }

    // MARK: - Article-list lead-in

    /// Mirrors the reported row: category tags + a duplicated headline + a
    /// byline/date/comment row glued to the body, all entity-encoded.
    func testLeadInDropsBylineChromeAndEntities() {
        let html = """
        <p>AAPL Company John Ternus John Ternus is taking a more &#8216;hands-on&#8217; \
        role in Apple&#8217;s design teams as CEO: report</p>
        <p>Michael Burkhardt | Oct 4 2026 - 8:15 am PT 3 Comments Since Jony Ive&#8217;s \
        departure from Apple in 2019, the company hasn&#8217;t had much of a true design leader.</p>
        """
        let record = ArticleRecord(
            title: "John Ternus is taking a more 'hands-on' role as CEO",
            extractedContent: html
        )
        let item = ArticleListItem(record: record)

        XCTAssertFalse(item.cleanSnippet.contains("Michael Burkhardt"))
        XCTAssertFalse(item.cleanSnippet.contains("Comments"))
        XCTAssertFalse(item.cleanSnippet.contains("&#"))
        XCTAssertTrue(item.cleanSnippet.hasPrefix("Since Jony Ive’s departure"))
    }

    func testPersistedMetadataLeadIsDetected() {
        let contaminated = "Michael Burkhardt | Oct 4 2026 - 8:15 am PT 3 Comments Since Jony Ive"
        XCTAssertTrue(ArticleListItem.looksLikeMetadataLead(contaminated))
        XCTAssertFalse(
            ArticleListItem.looksLikeMetadataLead(
                "Since Jony Ive's departure from Apple in 2019, the company has changed."
            )
        )
    }
}

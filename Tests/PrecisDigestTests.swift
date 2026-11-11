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

// Real headline regressions. These exercise candidate selection and acceptance
// independently of model availability; they do not claim to measure model accuracy.
final class StoryMatchingRegressionTests: XCTestCase {
    private func article(_ title: String, summary: String = "", feed: UUID = UUID()) -> ArticleListItem {
        var item = ArticleListItem(title: title, feedTitle: "Test", publishedDate: Date(timeIntervalSince1970: 1_000_000), isRead: false, isStarred: false, snippet: summary)
        item.feedID = feed
        return item
    }

    func testPochettinoParaphrasesReachSemanticReview() {
        let sky = article("Man Utd strike Pochettino agreement with Carrick set to depart")
        let bbc = article("Pochettino ready to accept Man Utd offer to replace Carrick")
        XCTAssertTrue(StoryMatching.isCandidate(sky, bbc))
        XCTAssertFalse(StoryMatching.isNearDuplicate(sky.title, bbc.title), "Paraphrases require event verification")
        XCTAssertEqual(StoryMatching.storyTerms("Man Utd"), StoryMatching.storyTerms("Manchester United"))
    }

    func testUnrelatedSportsHeadlinesDoNotReachReviewEvenWithSharedSummaryWords() {
        let summary = "Premier League football players are among the best players in the world."
        let king = article("Could King really become one of the best players in the world?", summary: summary)
        let bronze = article("Bronze named in World 11 for record ninth time", summary: summary)
        let suspensions = article("Which Premier League players are set for yellow card suspensions?", summary: summary)
        XCTAssertFalse(StoryMatching.isCandidate(king, bronze))
        XCTAssertFalse(StoryMatching.isCandidate(king, suspensions))
        XCTAssertFalse(StoryMatching.isCandidate(bronze, suspensions))
    }

    func testSportConflictOverridesIdenticalTextAndVectors() {
        let title: Set<String> = ["england", "australia", "final"]
        let first = StoryEvidence.Profile(title: title, body: title, names: ["england"], mainPerson: [], sport: "rugby-league", development: nil, vector: [1, 0])
        let second = StoryEvidence.Profile(title: title, body: title, names: ["england"], mainPerson: [], sport: "cricket", development: nil, vector: [1, 0])
        let result = StoryEvidence.evaluate(first, second)
        XCTAssertFalse(result.matches)
        XCTAssertEqual(result.reason, "different-sports")
    }

    func testSamePersonDifferentDevelopmentCannotStack() {
        let title: Set<String> = ["smith", "united", "manager", "injury"]
        let first = StoryEvidence.Profile(title: title, body: title, names: ["smith"], mainPerson: ["smith"], sport: "football", development: "appointment", vector: [1, 0])
        let second = StoryEvidence.Profile(title: title, body: title, names: ["smith"], mainPerson: ["smith"], sport: "football", development: "injury-withdrawal", vector: [1, 0])
        XCTAssertFalse(StoryEvidence.evaluate(first, second).matches)
    }

    func testDifferentMainPeopleCannotStackEvenWithIdenticalVectors() {
        let title: Set<String> = ["star", "return", "tennis", "january"]
        let first = StoryEvidence.Profile(title: title, body: title, names: ["raducanu"], mainPerson: ["raducanu"], sport: "tennis", development: "return", vector: [1, 0])
        let second = StoryEvidence.Profile(title: title, body: title, names: ["osaka"], mainPerson: ["osaka"], sport: "tennis", development: "return", vector: [1, 0])
        XCTAssertFalse(StoryEvidence.evaluate(first, second).matches)
    }

    func testSimilarityAloneCannotCreateStack() {
        let first = StoryEvidence.Profile(title: ["england", "australia"], body: [], names: [], mainPerson: [], sport: nil, development: nil, vector: [1, 0])
        XCTAssertFalse(StoryEvidence.evaluate(first, first).matches)
    }

    func testNormalizationPreservesNamesAndWholeWordBoundaries() {
        XCTAssertEqual(StoryEvidence.terms("O’Brien"), StoryEvidence.terms("O'Brien"))
        XCTAssertEqual(StoryEvidence.normalized("West Indies"), StoryEvidence.normalized("Windies"))
        XCTAssertEqual(StoryEvidence.normalized("German Utd"), "german utd")
    }

    func testMissingActionDoesNotOverrideKnownAction() {
        let title: Set<String> = ["smith", "united", "manager", "agreement"]
        let first = StoryEvidence.Profile(title: title, body: title, names: ["smith"], mainPerson: ["smith"], sport: "football", development: "appointment", vector: [1, 0])
        let second = StoryEvidence.Profile(title: title, body: title, names: ["smith"], mainPerson: ["smith"], sport: "football", development: nil, vector: [1, 0])
        XCTAssertFalse(StoryEvidence.evaluate(first, second).matches)
    }

    func testMissingEvidenceCannotBeReplacedByLexicalOverlap() {
        let p = StoryEvidence.Profile(title: ["team", "wins", "again"], body: [], names: [], mainPerson: [], sport: nil, development: nil, vector: nil)
        XCTAssertFalse(StoryEvidence.evaluate(p, p).matches)
    }

    func testStrongCorroboratedEvidenceWorksWithoutEmbeddingAsset() {
        let words: Set<String> = ["smith", "tennis", "return", "january", "tournament"]
        let p = StoryEvidence.Profile(title: words, body: words, names: ["smith"], mainPerson: ["smith"], sport: "tennis", development: "return", vector: nil)
        XCTAssertTrue(StoryEvidence.evaluate(p, p).matches)
    }

    func testContentCacheIsSymmetric() async {
        let first = article("Pochettino ready to accept Man Utd offer to replace Carrick", summary: "Mauricio Pochettino is ready to accept an offer from Manchester United to become their next head coach.")
        let second = article("Man Utd strike Pochettino agreement with Carrick set to depart", summary: "Manchester United have reached a verbal agreement in principle with Mauricio Pochettino to take over as head coach.")
        let service = StorySimilarityService()
        let forward = await service.areSameStory(first, second)
        let reverse = await service.areSameStory(second, first)
        XCTAssertEqual(forward, reverse)
        let path = await service.lastReviewPath
        XCTAssertEqual(path, .cached)
    }

    func testIdenticalHeadlinesCannotBypassSportAndDateSafeguards() {
        var first = article("England beat Australia")
        var second = article("England beat Australia")
        first.link = "https://www.bbc.co.uk/sport/rugby-league/articles/example"
        second.link = "https://www.skysports.com/cricket/news/example"
        XCTAssertFalse(StoryMatching.isExactDuplicate(first, second))
        second.link = first.link
        second.publishedDate = first.publishedDate!.addingTimeInterval(74 * 3600)
        XCTAssertFalse(StoryMatching.isExactDuplicate(first, second))
        first.cleanURL = "https://example.com/story"
        second.cleanURL = first.cleanURL
        XCTAssertTrue(StoryMatching.isExactDuplicate(first, second), "An identical canonical article URL is conclusive")
    }

    func testInflectionsAndHeadlineActionPrecedence() {
        XCTAssertTrue(StoryEvidence.terms("resigns").contains("resign"))
        XCTAssertTrue(StoryEvidence.terms("dies").contains("death"))
        let relocation = article("Treasury secretary relocates to military base after threats", summary: "The official moved from home to a military base after threats.")
        XCTAssertEqual(StoryEvidence.profile(relocation, embedding: nil).development, "relocation")
        let threats = article("Treasury secretary receives death threats", summary: "Police are investigating threats against the secretary.")
        XCTAssertEqual(StoryEvidence.profile(threats, embedding: nil).development, "threat")
    }

    func testCompanyAndCriminalInvestigationsRemainSeparate() {
        let company = article("Acme opens independent investigation into CEO's conduct", summary: "The company hired a law firm to investigate allegations against the chief executive.")
        let criminal = article("FBI investigating Acme CEO's conduct", summary: "The FBI is investigating allegations against the chief executive.")
        let a = StoryEvidence.profile(company, embedding: nil)
        let b = StoryEvidence.profile(criminal, embedding: nil)
        XCTAssertEqual(a.development, "internal-investigation")
        XCTAssertEqual(b.development, "criminal-investigation")
        XCTAssertEqual(StoryEvidence.evaluate(a, b).reason, "different-developments")
    }

    func testAcquittalAndConvictionCannotMatch() {
        let acquittal = article("Alex Smith found not guilty in fraud trial", summary: "The court found Smith not guilty.")
        let conviction = article("Alex Smith found guilty in fraud trial", summary: "The court found Smith guilty.")
        let a = StoryEvidence.profile(acquittal, embedding: nil)
        let b = StoryEvidence.profile(conviction, embedding: nil)
        XCTAssertEqual(a.development, "acquittal")
        XCTAssertEqual(b.development, "conviction")
        XCTAssertFalse(StoryEvidence.evaluate(a, b).matches)
    }

    func testCommemorationAndPoliticalMarchRemainSeparate() {
        let vigil = article("Thousands join silent march for shooting victims", summary: "Mourners joined a silent march to remember the victims.")
        let rally = article("Thousands join nationalist march", summary: "Crowds joined a nationalist political march.")
        let a = StoryEvidence.profile(vigil, embedding: nil)
        let b = StoryEvidence.profile(rally, embedding: nil)
        XCTAssertEqual(a.development, "commemoration")
        XCTAssertEqual(b.development, "protest")
        XCTAssertEqual(StoryEvidence.evaluate(a, b).reason, "different-developments")
    }

    func testReportedSourceIsNotMistakenForMainPerson() {
        let story = article("Trump says Jensen Huang faces investigation", summary: "The FBI is investigating the chief executive.")
        let profile = StoryEvidence.profile(story, embedding: nil)
        XCTAssertFalse(profile.mainPerson.contains("trump"))
        XCTAssertTrue(profile.mainPerson.contains("huang"))
    }

    func testCachedCandidateFeaturesAgreeWithDirectSelection() async {
        let first = article("Emma Smith returns to tennis in January")
        let second = article("Smith tennis comeback set for January")
        let service = StorySimilarityService()
        let features = await service.candidateFeatures(for: [first, second])
        XCTAssertEqual(features.count, 2)
        XCTAssertEqual(StoryMatching.isCandidate(first, second), StoryMatching.isCandidate(first, second, firstFeatures: features[first.id], secondFeatures: features[second.id]))
        let again = await service.candidateFeatures(for: [first, second])
        XCTAssertEqual(features[first.id]?.title, again[first.id]?.title)
    }

    func testDateAndFeedSafeguards() {
        let first = article("Pochettino accepts Manchester United appointment")
        var second = article(first.title, feed: first.feedID!)
        XCTAssertFalse(StoryMatching.isCandidate(first, second))
        second.feedID = UUID()
        second.publishedDate = first.publishedDate!.addingTimeInterval(73 * 3600)
        XCTAssertFalse(StoryMatching.isCandidate(first, second))
        second.publishedDate = nil
        XCTAssertFalse(StoryMatching.isCandidate(first, second))
    }

    func testRelatedMemberCannotBridgeTwoDifferentDevelopments() async {
        let first = article("Manchester United Pochettino appointment agreement")
        let member = article("Manchester United Pochettino manager appointment")
        let unrelated = article("Manchester United Pochettino player injury")
        let firstID = first.id, memberID = member.id, unrelatedID = unrelated.id
        let memberPrimary = await StoryMatching.primary(for: member, among: [first]) { _, _ in true }
        XCTAssertEqual(memberPrimary, firstID)
        let unrelatedPrimary = await StoryMatching.primary(for: unrelated, among: [first]) { a, b in
            // B and C could match; A and C must still be checked independently.
            a.id == memberID && b.id == unrelatedID
        }
        XCTAssertEqual(unrelatedPrimary, unrelatedID)
    }
}

/// A labelled RSS snapshot, including new held-out events and cross-topic negatives.
/// Opt-in because the corpus uses the installed Natural Language embedding asset.
final class StoryMatchingRealWorldTests: XCTestCase {
    private struct Corpus: Decodable {
        struct Article: Decodable {
            let id: String
            let source: String
            let title: String
            let summary: String
            let url: String
            let timestamp: Double
            let event: String?
        }
        struct Pair: Decodable {
            let first: String
            let second: String
            let sameEvent: Bool
            let split: String?
        }
        struct Acceptance: Decodable {
            let minimumRecall: Double
            let minimumHoldoutRecall: Double
        }
        let acceptance: Acceptance?
        let articles: [Article]
        let pairs: [Pair]
    }

    func testRealWorldPrecisionAndKnownRegressions() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PRECIS_STORY_BENCHMARK"] == "1" || ProcessInfo.processInfo.environment["PRECIS_LIVE_STORY_TESTS"] == "1", "Opt in with PRECIS_STORY_BENCHMARK=1")
        let fixture = ProcessInfo.processInfo.environment["PRECIS_STORY_FIXTURE"] ?? "StoryMatchingBenchmark.json"
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures").appendingPathComponent(fixture)
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: path))
        let service = StorySimilarityService()
        var feedIDs: [String: UUID] = [:]
        var articles: [String: ArticleListItem] = [:]
        for (index, article) in corpus.articles.enumerated() {
            if feedIDs[article.source] == nil { feedIDs[article.source] = UUID() }
            var item = ArticleListItem(id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012x", index + 1))!, title: article.title, feedTitle: article.source, publishedDate: Date(timeIntervalSince1970: article.timestamp), isRead: false, isStarred: false, snippet: article.summary, link: article.url)
            item.feedID = feedIDs[article.source]
            articles[article.id] = item
        }
        var rows: [[String: String]] = []
        var falseMatches = 0, missedMatches = 0, developmentMisses = 0, evidenceReviews = 0, reviewFailures = 0
        let pairs = corpus.pairs.filter {
            ProcessInfo.processInfo.environment["PRECIS_STORY_HARD_NEGATIVES_ONLY"] != "1"
                || ($0.first == "england-result-bbc" && $0.second != "japan-sky")
        }
        for pair in pairs {
            let first = try XCTUnwrap(articles[pair.first])
            let second = try XCTUnwrap(articles[pair.second])
            let candidate = StoryMatching.isCandidate(first, second)
            var match = false
            var path = "candidateRejected"
            var error = ""
            var reason = "candidateRejected"
            var similarity = ""
            if candidate {
                match = await service.areSameStory(first, second)
                let reviewPath = await service.lastReviewPath
                path = reviewPath.rawValue
                error = await service.lastReviewError ?? ""
                reason = await service.lastReviewReason
                similarity = String(await service.lastSimilarity ?? -1)
                if reviewPath == .evidence { evidenceReviews += 1 }
                if !(await service.lastReviewError ?? "").isEmpty { reviewFailures += 1 }
            }
            if match && !pair.sameEvent { falseMatches += 1 }
            if !match && pair.sameEvent {
                missedMatches += 1
                if pair.split != "holdout" { developmentMisses += 1 }
            }
            let row = ["split": pair.split ?? "development", "reason": reason, "similarity": similarity, "first": pair.first, "second": pair.second, "expected": String(pair.sameEvent), "matched": String(match), "path": path, "error": error]
            rows.append(row)
            print("REAL_STORY_PAIR \(pair.first) / \(pair.second): expected=\(pair.sameEvent), matched=\(match), path=\(path), reason=\(reason), similarity=\(similarity), error=\(error)")
        }
        if let output = ProcessInfo.processInfo.environment["PRECIS_STORY_RESULTS"] {
            try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output))
        }
        // Exercise the same primary-only assembly used by the view model.
        // Accurate pair scores alone do not prove that final stacks are safe.
        let fixtureByID = Dictionary(uniqueKeysWithValues: corpus.articles.map { (articles[$0.id]!.id, $0) })
        let recent = StoryMatching.recentArticles(Array(articles.values))
        let features = Dictionary(uniqueKeysWithValues: recent.map { ($0.id, StoryMatching.CandidateFeatures($0)) })
        var primaries: [ArticleListItem] = []
        var groups: [UUID: [UUID]] = [:]
        for article in recent {
            let primary = await StoryMatching.primary(for: article, among: primaries, features: features) { a, b in
                await service.areSameStory(a, b)
            }
            groups[primary, default: []].append(article.id)
            if primary == article.id { primaries.append(article) }
        }
        let falseGroups = groups.values.filter { Set($0.compactMap { fixtureByID[$0]?.event }).count > 1 }.count
        let expectedGroups = Set(corpus.articles.compactMap(\.event)).count
        print("REAL_STORY_GROUPS expected=\(expectedGroups) actual=\(groups.count) falseGroups=\(falseGroups)")
        XCTAssertEqual(falseGroups, 0, "Final article stacks must not combine different developments")
        let groupRows = groups.values.map { ids in ids.compactMap { fixtureByID[$0]?.id }.sorted() }.sorted { ($0.first ?? "") < ($1.first ?? "") }
        let groupReport = try JSONSerialization.data(withJSONObject: groupRows, options: [.prettyPrinted, .sortedKeys])
        if let output = ProcessInfo.processInfo.environment["PRECIS_STORY_RESULTS"] {
            try groupReport.write(to: URL(fileURLWithPath: output + ".groups.json"))
        }
        let groupAttachment = XCTAttachment(data: groupReport, uniformTypeIdentifier: "public.json")
        groupAttachment.name = "Assembled article stacks"
        groupAttachment.lifetime = .keepAlways
        add(groupAttachment)
        let report = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: report, uniformTypeIdentifier: "public.json")
        attachment.name = "Real-world story matching results"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("REAL_STORY_TOTAL pairs=\(pairs.count) falseMatches=\(falseMatches) missedMatches=\(missedMatches) evidenceReviews=\(evidenceReviews) reviewFailures=\(reviewFailures)")
        XCTAssertEqual(reviewFailures, 0, "Evidence evaluation must not fail")
        XCTAssertGreaterThan(evidenceReviews, 0)
        XCTAssertEqual(falseMatches, 0)
        // Automatic stacking prioritises precision. Holdout recall is measured
        // in the attachment, not silently relabelled or tuned into a passing score.
        if let acceptance = corpus.acceptance {
            let positives = rows.filter { $0["expected"] == "true" }
            let holdout = positives.filter { $0["split"] == "holdout" }
            let recall = Double(positives.filter { $0["matched"] == "true" }.count) / Double(max(1, positives.count))
            let holdoutRecall = Double(holdout.filter { $0["matched"] == "true" }.count) / Double(max(1, holdout.count))
            XCTAssertGreaterThanOrEqual(recall, acceptance.minimumRecall)
            XCTAssertGreaterThanOrEqual(holdoutRecall, acceptance.minimumHoldoutRecall)
        } else {
            XCTAssertEqual(developmentMisses, 0, "Previously established matches must remain recognised")
        }
    }
}

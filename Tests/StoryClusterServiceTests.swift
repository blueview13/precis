import FoundationModels
import XCTest
import SwiftData
@testable import Precis

final class StoryClusterServiceTests: XCTestCase {
    private func article(_ title: String, body: String = "", days: Double = 0, id: UUID = UUID()) -> ArticleListItem {
        ArticleListItem(id: id, title: title, feedTitle: "Test", publishedDate: Date(timeIntervalSince1970: 1_800_000_000 + days * 86400), snippet: body)
    }
    private let same = StoryReview(relation: .sameEvent, score: 1, provider: "apple", reason: "test")

    func testSemanticRetrievalWithoutSharedHeadlineWordsAndSameFeed() async {
        let service = StoryClusterService(useSystemEmbeddings: false, encoder: { _ in [1, 0] }, reviewer: { _, _ in StoryReview(relation: .sameEvent, score: 1, provider: "apple", reason: "test") })
        let a = article("Mayor quits office")
        let b = article("City leader announces resignation")
        let groups = await service.update([a,b])
        XCTAssertEqual(groups[a.id], groups[b.id])
    }

    func testRestartReadStateAndPartialFeedPreserveMembership() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("clusters.json")
        let service = StoryClusterService(storeURL: url, useSystemEmbeddings: false, encoder: { _ in [1, 0] }, reviewer: { _, _ in StoryReview(relation: .sameEvent, score: 1, provider: "apple", reason: "test") })
        let a = article("Mayor quits office"), b = article("City leader resigns")
        let first = await service.update([a,b])
        var read = b; read.isRead = true
        let second = await service.update([read])
        XCTAssertEqual(second[b.id], first[b.id])
        let restored = StoryClusterService(storeURL: url, useAppleIntelligence: false, useSystemEmbeddings: false)
        let membership = await restored.memberships(for: [a.id,b.id])
        XCTAssertEqual(first, membership)
        await restored.removeArticles([a.id])
        let afterDelete = await restored.memberships(for: [a.id,b.id])
        XCTAssertNil(afterDelete[a.id])
        XCTAssertEqual(afterDelete[b.id], first[b.id])
    }

    func testPipelineUpgradePreservesMembershipsUntilSnapshotRefreshesEntries() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("clusters.json")
        let a = article("Riverton approves a new library")
        let original = StoryClusterService(storeURL: url, useAppleIntelligence: false, useSystemEmbeddings: false)
        let before = await original.update([a])
        var saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var entries = try XCTUnwrap(saved["entries"] as? [Any])
        var entry = try XCTUnwrap(entries[1] as? [String: Any])
        entry["pipelineVersion"] = "events-v6-apple-system-only"
        entries[1] = entry
        saved["entries"] = entries
        saved["version"] = "events-v6-apple-system-only"
        try JSONSerialization.data(withJSONObject: saved).write(to: url)

        let upgraded = StoryClusterService(storeURL: url, useAppleIntelligence: false, useSystemEmbeddings: false)
        let retained = await upgraded.memberships(for: [a.id])
        XCTAssertEqual(retained[a.id], before[a.id])
        let refreshed = await upgraded.update([a])
        XCTAssertEqual(refreshed[a.id], before[a.id])
    }

    func testBridgeDoesNotMergeIncompatibleEvents() async {
        let service = StoryClusterService(useSystemEmbeddings: false, encoder: { _ in [1,0] }, reviewer: { a,b in
            let incompatible = (a.contains("Alpha") && b.contains("Gamma")) || (a.contains("Gamma") && b.contains("Alpha"))
            return StoryReview(relation: incompatible ? .relatedDevelopment : .sameEvent, score: 1, provider: "apple", reason: "test")
        })
        let a = article("Alpha event", days: 0), b = article("Beta event", days: 1), c = article("Gamma event", days: 2)
        let groups = await service.update([a,b,c])
        XCTAssertEqual(groups[a.id], groups[b.id])
        XCTAssertNotEqual(groups[a.id], groups[c.id])
    }

    func testContentUpdateReassessesMembership() async {
        let service = StoryClusterService(useSystemEmbeddings: false, encoder: { _ in [1,0] }, reviewer: { a,b in
            StoryReview(relation: a.contains("verdict") || b.contains("verdict") ? .relatedDevelopment : .sameEvent,
                        score: 1, provider: "apple", reason: "test")
        })
        let a = article("Police investigate case"), b = article("Detectives open inquiry", days: 1)
        let first = await service.update([a,b])
        XCTAssertEqual(first[a.id], first[b.id])
        let changed = article("Court issues verdict", days: 1, id: b.id)
        let second = await service.update([a,changed])
        XCTAssertNotEqual(second[a.id], second[b.id])
    }

    func testUnavailableAndThrowingReviewerUseConservativeEvidence() async {
        let a = article("City council approves a library"), b = article("City councillors approve library funding")
        let offline = StoryClusterService(useAppleIntelligence: false, useSystemEmbeddings: false)
        let failed = StoryClusterService(useSystemEmbeddings: false, reviewer: { _,_ in throw CocoaError(.featureUnsupported) })
        let normal = await offline.update([a,b])
        let fallback = await failed.update([a,b])
        XCTAssertEqual(normal[a.id] == normal[b.id], fallback[a.id] == fallback[b.id])
        let entries = await failed.entriesForEvaluation()
        XCTAssertTrue(entries.values.allSatisfy { $0.encoderVersion == "evidence-only" })
        let error = await failed.lastModelError
        XCTAssertNotNil(error)
    }

    func testConcurrentIngestionIsSerializedAndIdempotent() async {
        let service = StoryClusterService(useSystemEmbeddings: false, encoder: { _ in [1,0] }, reviewer: { _,_ in
            try await Task.sleep(for: .milliseconds(10))
            return StoryReview(relation: .sameEvent, score: 1, provider: "apple", reason: "test")
        })
        let a = article("Mayor quits office"), b = article("City leader resigns")
        async let one = service.update([a])
        async let two = service.update([b,a])
        _ = await (one,two)
        let entries = await service.entriesForEvaluation()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[a.id]?.clusterID, entries[b.id]?.clusterID)
    }

    func testMissingModelsAndDatesFailConservatively() async {
        let service = StoryClusterService(useAppleIntelligence: false, useSystemEmbeddings: false)
        var a = article("A distant star is discovered"), b = article("Council raises parking fees")
        a.publishedDate = nil; b.publishedDate = nil
        let groups = await service.update([a,b])
        XCTAssertNotEqual(groups[a.id], groups[b.id])
        XCTAssertEqual(groups.count, 2)
    }

    func testCancelledUpdatePreservesExistingMemberships() async throws {
        let service = StoryClusterService(useSystemEmbeddings: false, encoder: { _ in [1,0] }, reviewer: { _,_ in
            try await Task.sleep(for: .seconds(2))
            return StoryReview(relation: .sameEvent, score: 1, provider: "apple", reason: "test")
        })
        let a = article("First event"), b = article("Second report")
        let original = await service.update([a])
        let task = Task { await service.update([b]) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        _ = await task.value
        let groups = await service.memberships(for: [a.id,b.id])
        XCTAssertEqual(groups[a.id], original[a.id])
        XCTAssertNil(groups[b.id])
    }

    func testCorruptStoreRecoversAndReportsReadFailure() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("corrupt".utf8).write(to: url)
        let service = StoryClusterService(storeURL: url, useAppleIntelligence: false, useSystemEmbeddings: false)
        let groups = await service.memberships(for: [])
        XCTAssertTrue(groups.isEmpty)
        let error = await service.lastPersistenceError
        XCTAssertNotNil(error)
    }

    func testUpdatingOriginalAnchorCanSplitWithoutMovingOtherMembers() async {
        let service = StoryClusterService(useSystemEmbeddings: false, encoder: { _ in [1,0] }, reviewer: { a,b in
            StoryReview(relation: a.contains("verdict") || b.contains("verdict") ? .relatedDevelopment : .sameEvent,
                        score: 1, provider: "apple", reason: "test")
        })
        let a = article("Police investigate case"), b = article("Detectives open inquiry", days: 1)
        let first = await service.update([a,b])
        let changed = article("Court issues verdict", id: a.id)
        let second = await service.update([changed,b])
        XCTAssertNotEqual(second[a.id], second[b.id])
        XCTAssertEqual(second[b.id], first[b.id])
    }

    func testDeletedArticleCannotReturnFromStaleIngestionSnapshot() async {
        let service = StoryClusterService(useAppleIntelligence: false, useSystemEmbeddings: false)
        let a = article("Old report")
        _ = await service.update([a])
        await service.removeArticles([a.id])
        let result = await service.update([a])
        XCTAssertNil(result[a.id])
    }

    func testNoEightHundredArticleLimit() async {
        let service = StoryClusterService(useAppleIntelligence: false, useSystemEmbeddings: false)
        let articles = (0..<805).map { article("Report \($0)", days: Double($0) * 20) }
        let result = await service.update(articles)
        XCTAssertEqual(result.count, 805)
    }

    func testAppleReviewBudgetAllowsMoreCandidateReviews() async {
        actor Counter {
            var value = 0
            func increment() { value += 1 }
        }
        let counter = Counter()
        let service = StoryClusterService(useSystemEmbeddings: false, encoder: { _ in [1,0] }, reviewer: { _,_ in
            await counter.increment()
            return StoryReview(relation: .unrelated, score: 0, provider: "apple", reason: "test")
        })
        _ = await service.update((0..<20).map { article("Different report \($0)", days: Double($0) / 100) })
        let calls = await counter.value
        XCTAssertGreaterThan(calls, 12)
        XCTAssertLessThanOrEqual(calls, 96)
    }

    func testGroundedAppleReviewCanBridgeLowSimilarityHeadlines() async {
        let service = StoryClusterService(useSystemEmbeddings: false, encoder: { text in
            text.contains("Riverton backs") ? [0.3, sqrt(0.91)] : [1, 0]
        }, reviewer: { _,_ in
            StoryReview(relation: .sameEvent, score: 1, provider: "apple", reason: "grounded-event-review")
        })
        let a = article("Riverton approves Oak Street community library", body: "The council voted to approve the library on Monday.")
        let b = article("Riverton backs a new public reading room", body: "Councillors voted for the Oak Street library project on Monday.", days: 1)
        let groups = await service.update([a,b])
        XCTAssertEqual(groups[a.id], groups[b.id], "A source-grounded Apple review should recover a story that the narrow text gate misses")
    }

    @MainActor
    func testFeedIngestionQueuesClusteringWithoutAViewModel() async throws {
        let configuration = ModelConfiguration(schema: ModelContainerProvider.schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ModelContainerProvider.schema, configurations: configuration)
        let context = ModelContext(container)
        let feed = FeedRecord(title: "Test feed", url: "https://example.com/feed")
        context.insert(feed)
        try context.save()
        let clusters = StoryClusterService(useAppleIntelligence: false, useSystemEmbeddings: false)
        let processor = ArticleIngestProcessor(storyClusters: clusters)
        let count = try await processor.ingestParsed([ParsedFeedEntry(title: "Council approves library", content: "The council approved a new library.")], feedID: feed.id, container: container)
        XCTAssertEqual(count, 1)
        var entries = await clusters.entriesForEvaluation()
        for _ in 0..<100 where entries.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
            entries = await clusters.entriesForEvaluation()
        }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.values.first?.title, "Council approves library")
    }

    func testAppleCannotOverrideExplicitInvestigationConflict() async {
        let service = StoryClusterService(useSystemEmbeddings: false, encoder: { _ in [1,0] }, reviewer: { _,_ in
            StoryReview(relation: .sameEvent, score: 1, provider: "apple", reason: "incorrect model answer")
        })
        let a = article("Acme opens independent investigation into CEO", body: "The company hired a law firm to investigate its chief executive.")
        let b = article("FBI investigates Acme CEO", body: "The FBI is conducting a criminal investigation into the chief executive.")
        let groups = await service.update([a,b])
        XCTAssertNotEqual(groups[a.id], groups[b.id])
        XCTAssertFalse(StoryPairFeatures.developmentsConflict("investigation", "criminal-investigation"))
        XCTAssertTrue(StoryPairFeatures.developmentsConflict("internal-investigation", "criminal-investigation"))
    }

    func testLiveAppleEventReview() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PRECIS_APPLE_STORY_TEST"] == "1", "Opt-in live model test")
        try XCTSkipUnless(SystemLanguageModel.default.isAvailable, "Apple Intelligence is unavailable on this Mac")
        let reviewer = AppleStoryEventReviewer()
        let a = "Headline: Council approves new library\nOpening: On Monday Riverton council approved a new library on Oak Street."
        let b = "Headline: Riverton gives Oak Street library green light\nOpening: Councillors voted on Monday to approve construction of a new library on Oak Street."
        let c = "Headline: Riverton library opens\nOpening: The Oak Street library opened to readers on Friday after two years of construction."
        let positive = try await reviewer.review(a,b)
        let negative = try await reviewer.review(a,c)
        XCTAssertEqual(positive?.relation, .sameEvent)
        XCTAssertNotEqual(negative?.relation, .sameEvent)
    }

    func testLiveAppleReviewCanCreateStackBelowLocalSimilarityThreshold() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PRECIS_APPLE_STORY_TEST"] == "1", "Opt-in live model test")
        try XCTSkipUnless(SystemLanguageModel.default.isAvailable, "Apple Intelligence is unavailable on this Mac")
        let service = StoryClusterService(useSystemEmbeddings: false, encoder: { text in
            text.contains("Riverton gives") ? [0.3, sqrt(0.91)] : [1, 0]
        })
        let a = article("Council approves new library", body: "On Monday Riverton council approved a new library on Oak Street.")
        let b = article("Riverton gives Oak Street library green light", body: "Councillors voted on Monday to approve construction of a new library on Oak Street.", days: 1)
        let groups = await service.update([a,b])
        XCTAssertEqual(groups[a.id], groups[b.id], "Apple's grounded decision should stack paraphrases below the local semantic threshold")
    }
}

final class SemanticStoryBenchmarkTests: XCTestCase {
    struct Corpus: Decodable {
        struct Article: Decodable { let id: String; let title: String; let summary: String; let url: String; let timestamp: Double; let event: String? }
        struct Pair: Decodable { let first: String; let second: String; let sameEvent: Bool; let split: String? }
        let articles: [Article]
        let pairs: [Pair]
    }
    func testExportAndEvaluateSemanticPipeline() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PRECIS_SEMANTIC_BENCHMARK"] == "1", "Opt-in benchmark")
        let fixture = ProcessInfo.processInfo.environment["PRECIS_STORY_FIXTURE"] ?? "StoryMatchingBenchmark.json"
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures").appendingPathComponent(fixture)
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: path))
        let service = StoryClusterService(useAppleIntelligence: ProcessInfo.processInfo.environment["PRECIS_APPLE_STORY_TEST"] == "1")
        var articles: [String: ArticleListItem] = [:]
        for (index, a) in corpus.articles.enumerated() {
            articles[a.id] = ArticleListItem(id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012x", index + 1))!, title: a.title, feedTitle: "Fixture", publishedDate: Date(timeIntervalSince1970: a.timestamp), snippet: a.summary, link: a.url)
        }
        let start = Date()
        let groups = await service.update(Array(articles.values))
        let entries = await service.entriesForEvaluation()
        XCTAssertTrue(entries.values.allSatisfy { ["apple-natural-language-english", "evidence-only"].contains($0.encoderVersion) })
        var rows: [[String: Any]] = []
        var falseMatches = 0, hits = 0, positives = 0, stackFalse = 0, stackHits = 0
        for pair in corpus.pairs {
            let a = try XCTUnwrap(entries[articles[pair.first]!.id]), b = try XCTUnwrap(entries[articles[pair.second]!.id])
            let result = await service.reviewPair(a,b)
            let stacked = groups[a.id] == groups[b.id]
            if pair.sameEvent { positives += 1; if result.matches { hits += 1 }; if stacked { stackHits += 1 } }
            else { if result.matches { falseMatches += 1 }; if stacked { stackFalse += 1 } }
            rows.append(["first": pair.first, "second": pair.second, "sameEvent": pair.sameEvent,
                         "split": pair.split ?? "development", "features": StoryPairFeatures.values(a.profile,b.profile),
                         "matched": result.matches, "score": result.score, "provider": result.provider, "stacked": stacked])
        }
        var reversedOrderAgreement: Bool? = nil
        if ProcessInfo.processInfo.environment["PRECIS_STREAMING_REPLAY"] == "1" {
            let replay = StoryClusterService(useAppleIntelligence: false)
            for article in articles.values.sorted(by: { ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast) }) {
                _ = await replay.update([article])
            }
            let reversed = await replay.memberships(for: Set(articles.values.map(\.id)))
            func partition(_ assignments: [UUID: UUID]) -> Set<String> {
                Set(Dictionary(grouping: assignments.keys, by: { assignments[$0]! }).values.map { $0.map(\.uuidString).sorted().joined(separator: ",") })
            }
            reversedOrderAgreement = partition(groups) == partition(reversed)
            XCTAssertEqual(reversedOrderAgreement, true, "One-at-a-time reverse arrival should reproduce the batch partition")
        }
        var report: [String: Any] = ["fixture":fixture, "featureNames":StoryPairFeatures.names, "pairs":rows,
                                    "positives":positives,"hits":hits,"falseMatches":falseMatches,"stackHits":stackHits,
                                    "stackFalseMatches":stackFalse,"seconds":Date().timeIntervalSince(start),
                                    "model":StoryClusterService.pipelineVersion]
        if let reversedOrderAgreement { report["reversedOrderAgreement"] = reversedOrderAgreement }
        if let output = ProcessInfo.processInfo.environment["PRECIS_STORY_RESULTS"] {
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]).write(to: URL(fileURLWithPath: output))
        }
        print("SEMANTIC_RESULT \(fixture): pairs \(hits)/\(positives), false \(falseMatches); stacks \(stackHits)/\(positives), false \(stackFalse); seconds \(Date().timeIntervalSince(start))")
        // This is a new Apple-only policy; record recall without carrying forward the removed
        // ensemble's acceptance claims. False stacks remain an explicit regression failure.
        XCTAssertEqual(stackFalse, 0, "Automatic stacks must not merge labelled different events")
    }
}

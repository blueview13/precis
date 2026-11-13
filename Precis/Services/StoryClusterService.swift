import CryptoKit
import Foundation
import NaturalLanguage

extension Notification.Name {
    static let storyClustersDidChange = Notification.Name("Precis.storyClustersDidChange")
}

/// One writer for ingestion, view-model refreshes and enrichment. Membership is independent of UI filters.
actor StoryClusterService {
    static let shared = StoryClusterService(storeURL: defaultStoreURL)
    static var defaultStoreURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Precis/StoryClusters-v1.json")
    }
    static let pipelineVersion = "events-v14-incremental-clustering"
    typealias Reviewer = @Sendable (String, String) async throws -> StoryReview?
    typealias Encoder = @Sendable (String) throws -> [Double]

    struct Entry: Codable, Sendable {
        let id: UUID
        var clusterID: UUID
        let fingerprint: String
        var pipelineVersion: String? = StoryClusterService.pipelineVersion
        var reviewedAt: Date?
        let title: String
        let lead: String
        let url: String?
        let date: Date?
        let receivedAt: Date
        var language: String?
        var profile: StoryEvidence.Profile
        let encoderVersion: String
        var review: StoryReview
        var reviewText: String { "Headline: \(title)\nOpening: \(lead)" }
    }
    struct AssignmentChange: Codable, Sendable {
        let articleID: UUID
        let previous: UUID
        let current: UUID
        let date: Date
    }
    private struct Store: Codable {
        var version = StoryClusterService.pipelineVersion
        var entries: [UUID: Entry] = [:]
        var changes: [AssignmentChange] = []
        var deletedIDs: Set<UUID>? = []
    }
    private let storeURL: URL?
    private let reviewer: Reviewer?
    private let injectedEncoder: Encoder?
    private let useSystemEmbeddings: Bool
    private var systemEmbedding: NLEmbedding?
    private var embeddingAttempted = false
    private var store = Store()
    private var loaded = false
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let appleReviewBudgetPerUpdate = 96
    private var remainingAppleReviews = 96
    private var pairCache: [String: StoryReview] = [:]
    private(set) var lastPersistenceError: String?
    private(set) var lastModelError: String?

    init(storeURL: URL? = nil, useAppleIntelligence: Bool = true, useSystemEmbeddings: Bool = true,
         encoder: Encoder? = nil, reviewer: Reviewer? = nil) {
        self.storeURL = storeURL
        self.useSystemEmbeddings = useSystemEmbeddings
        self.injectedEncoder = encoder
        if let reviewer { self.reviewer = reviewer }
        else if useAppleIntelligence { self.reviewer = { a, b in try await AppleStoryEventReviewer().review(a, b) } }
        else { self.reviewer = nil }
    }

    private func acquire() async {
        if busy { await withCheckedContinuation { waiters.append($0) } }
        else { busy = true }
    }
    private func release() {
        if waiters.isEmpty { busy = false }
        else { waiters.removeFirst().resume() }
    }
    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let storeURL, FileManager.default.fileExists(atPath: storeURL.path) else { return }
        do {
            let saved = try JSONDecoder().decode(Store.self, from: Data(contentsOf: storeURL))
            store = saved
            // Keep the old index intact while a current article snapshot is
            // loaded. update(_:) refreshes entries as they appear in snapshots;
            // dropping older entries here would erase memberships when startup
            // initially supplies only a partial list.
            store.version = Self.pipelineVersion
        } catch { lastPersistenceError = "Could not read story index: \(error.localizedDescription)" }
    }
    private func persist() {
        guard let storeURL else { return }
        do {
            try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(store).write(to: storeURL, options: .atomic)
            lastPersistenceError = nil
        } catch { lastPersistenceError = "Could not save story index: \(error.localizedDescription)" }
    }

    func memberships(for ids: Set<UUID>) -> [UUID: UUID] {
        load()
        return store.entries.filter { ids.contains($0.key) }.mapValues(\.clusterID)
    }
    func entriesForEvaluation() -> [UUID: Entry] { load(); return store.entries }

    static func fingerprint(_ article: ArticleListItem) -> String {
        let text = [article.title, String(article.articleBody.prefix(1800)), article.cleanURL ?? "",
                    article.publishedDate.map { String($0.timeIntervalSince1970) } ?? ""].joined(separator: "\u{0}")
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func makeEntry(_ article: ArticleListItem, now: Date) -> Entry {
        if !embeddingAttempted {
            embeddingAttempted = true
            if useSystemEmbeddings && injectedEncoder == nil {
                systemEmbedding = NLEmbedding.sentenceEmbedding(for: .english)
            }
        }
        var profile = StoryEvidence.profile(article, embedding: systemEmbedding)
        let lead = String(article.articleBody.prefix(1800))
        var version = systemEmbedding == nil ? "evidence-only" : "apple-natural-language-english"
        if let injectedEncoder {
            do {
                profile.vector = try injectedEncoder(article.title + ". " + lead)
                profile.headlineVector = try injectedEncoder(article.title)
                profile.openingVector = try injectedEncoder(lead)
                version = "injected"
            } catch { lastModelError = "System embedding failed: \(error.localizedDescription)" }
        }
        return Entry(id: article.id, clusterID: article.id, fingerprint: Self.fingerprint(article),
                     title: article.title, lead: lead, url: article.cleanURL, date: article.publishedDate,
                     receivedAt: store.entries[article.id]?.receivedAt ?? now,
                     language: NLLanguageRecognizer.dominantLanguage(for: article.title + ". " + lead)?.rawValue, profile: profile,
                     encoderVersion: version, review: StoryReview(relation: .insufficientEvidence, score: 0,
                                                                 provider: version, reason: "new-event"))
    }

    /// Snapshots can be partial (one newly ingested feed), so absence never deletes another feed's membership.
    /// Existing assignments remain visible throughout work. Deletion is an explicit, separate operation.
    @discardableResult
    func update(_ articles: [ArticleListItem], now: Date = Date()) async -> [UUID: UUID] {
        await acquire()
        defer { release() }
        load()
        guard !Task.isCancelled else { return memberships(for: Set(articles.map(\.id))) }
        let sorted = articles.sorted {
            let a = $0.publishedDate ?? now, b = $1.publishedDate ?? now
            return a == b ? $0.id.uuidString < $1.id.uuidString : a < b
        }
        remainingAppleReviews = appleReviewBudgetPerUpdate
        var changed = false
        var updatesSincePersist = 0
        var affectedClusters: Set<UUID> = []
        for article in sorted {
            if Task.isCancelled { break }
            if store.deletedIDs?.contains(article.id) == true { continue }
            let previous = store.entries[article.id]
            let fingerprint = Self.fingerprint(article)
            let unchanged = previous?.fingerprint == fingerprint && previous?.pipelineVersion == Self.pipelineVersion
            let retryUncertain = reviewer != nil && previous?.review.matches == false
                && now.timeIntervalSince(previous?.reviewedAt ?? .distantPast) >= 6 * 3600
                && abs(now.timeIntervalSince(article.publishedDate ?? now)) <= 14 * 86400
            if unchanged && !retryUncertain { continue }
            var entry = unchanged ? previous! : makeEntry(article, now: now)
            entry.clusterID = article.id
            // Updating a singleton preserves its stable identifier, even after earlier merges/splits.
            let oldCluster = previous?.clusterID
            let otherMembers = store.entries.values.filter { $0.id != article.id && $0.clusterID == oldCluster }
            if previous != nil && otherMembers.isEmpty { entry.clusterID = oldCluster ?? article.id }
            else if otherMembers.contains(where: { $0.clusterID == entry.clusterID }) { entry.clusterID = UUID() }
            let candidates = candidateClusters(for: entry)
            var accepted: [(UUID, Double, StoryReview)] = []
            for (clusterID, members, retrievalScore) in candidates {
                if Task.isCancelled { break }
                let representatives = representatives(of: members, near: entry)
                var reviews: [StoryReview] = []
                for representative in representatives {
                    let review = await reviewPair(entry, representative)
                    reviews.append(review)
                    if !review.matches { break }
                }
                if !reviews.isEmpty && reviews.allSatisfy(\.matches) {
                    accepted.append((clusterID, retrievalScore, reviews[0]))
                }
            }
            guard !Task.isCancelled else { break }
            accepted.sort { $0.1 > $1.1 }
            // Ambiguous placement remains visible as a singleton; do not collapse distinct events through a bridge.
            if let best = accepted.first, accepted.count == 1 || best.1 - accepted[1].1 >= 0.06 {
                entry.clusterID = best.0
                entry.review = best.2
            }
            if let previous, previous.clusterID != entry.clusterID {
                store.changes.append(AssignmentChange(articleID: article.id, previous: previous.clusterID, current: entry.clusterID, date: now))
            }
            entry.reviewedAt = now
            store.entries[article.id] = entry
            affectedClusters.insert(entry.clusterID)
            changed = true
            updatesSincePersist += 1
            if store.changes.count > 1000 { store.changes.removeFirst(store.changes.count - 1000) }
            if updatesSincePersist >= 25 {
                persist()
                notify()
                updatesSincePersist = 0
            }
            await Task.yield()
        }
        if !Task.isCancelled {
            await reconcile(affectedClusters, now: now)
            store.version = Self.pipelineVersion
        }
        if changed { persist(); notify() }
        return memberships(for: Set(articles.map(\.id)))
    }

    /// Revisit neighbouring fragments after ingestion/enrichment. Merges need every cross-member
    /// comparison to agree at high confidence. Large clusters remain separate instead of sampling
    /// away a contradictory member. Reconciliation uses conservative evidence so a feed burst cannot trigger
    /// hundreds of generative calls, and records every membership change for diagnosis/rollback.
    private func reconcile(_ affected: Set<UUID>, now: Date) async {
        for clusterID in affected.sorted(by: { $0.uuidString < $1.uuidString }) {
            if Task.isCancelled { return }
            let members = store.entries.values.filter { $0.clusterID == clusterID }
            guard !members.isEmpty, members.count <= 12,
                  let anchor = members.min(by: { ($0.date ?? $0.receivedAt) < ($1.date ?? $1.receivedAt) }) else { continue }
            let candidates = candidateClusters(for: anchor).filter { $0.0 != clusterID && $0.1.count <= 12 }.prefix(3)
            var compatible: [(UUID, [Entry])] = []
            for (otherID, others, _) in candidates {
                var consistent = true
                for a in members {
                    for b in others {
                        let review = await reviewPair(a, b, useApple: false)
                        if !review.matches || review.score < 0.9 { consistent = false; break }
                    }
                    if !consistent || Task.isCancelled { break }
                }
                if consistent { compatible.append((otherID, others)) }
            }
            guard !Task.isCancelled else { return }
            // Multiple plausible clusters indicate ambiguity, not permission to bridge them.
            guard compatible.count == 1, let other = compatible.first else { continue }
            let otherAnchor = other.1.min { ($0.date ?? $0.receivedAt) < ($1.date ?? $1.receivedAt) }!
            let keep = (anchor.date ?? anchor.receivedAt) <= (otherAnchor.date ?? otherAnchor.receivedAt) ? clusterID : other.0
            let remove = keep == clusterID ? other.0 : clusterID
            for id in store.entries.keys.sorted(by: { $0.uuidString < $1.uuidString }) where store.entries[id]?.clusterID == remove {
                store.entries[id]?.clusterID = keep
                store.changes.append(AssignmentChange(articleID: id, previous: remove, current: keep, date: now))
            }
            if store.changes.count > 1000 { store.changes.removeFirst(store.changes.count - 1000) }
        }
    }

    func removeArticles(_ ids: Set<UUID>) async {
        await acquire()
        defer { release() }
        load()
        store.deletedIDs = (store.deletedIDs ?? []).union(ids)
        for id in ids { store.entries.removeValue(forKey: id) }
        persist()
        notify()
    }

    private func notify() {
        NotificationCenter.default.post(name: .storyClustersDidChange, object: nil)
    }

    private func candidateClusters(for entry: Entry) -> [(UUID, [Entry], Double)] {
        let date = entry.date ?? entry.receivedAt
        let eligible = store.entries.values.filter {
            $0.id != entry.id && abs(($0.date ?? $0.receivedAt).timeIntervalSince(date)) <= 90 * 86400
        }
        let groups = Dictionary(grouping: eligible, by: \.clusterID)
        return groups.compactMap { id, members -> (UUID, [Entry], Double)? in
            let similarities = members.map { similarity(entry, $0) }
            let best = similarities.max() ?? 0
            let vectors = members.filter { $0.encoderVersion == entry.encoderVersion }.compactMap { $0.profile.vector }
            var centroid = [Double](repeating: 0, count: entry.profile.vector?.count ?? 0)
            for vector in vectors where vector.count == centroid.count {
                for i in centroid.indices { centroid[i] += vector[i] }
            }
            let centralSimilarity = StoryPairFeatures.cosine(entry.profile.vector ?? [], centroid)
            let lexical = members.contains { entry.profile.title.intersection($0.profile.title).count >= 2 }
            let exact = members.contains { entry.url != nil && entry.url == $0.url }
            let entityAnchor = members.contains { !entry.profile.names.isDisjoint(with: $0.profile.names) }
            // NaturalLanguage embeddings shortlist substantially more broadly;
            // a shared named person or organization also brings paraphrased coverage
            // to the same-event reviewer. Entity overlap alone never creates a stack.
            guard best >= 0.25 || lexical || exact || entityAnchor else { return nil }
            // Recent candidates rank ahead of equally similar older coverage; time is not event identity.
            let age = members.map { abs(($0.date ?? $0.receivedAt).timeIntervalSince(date)) }.min() ?? 0
            guard age <= 14 * 86400 || (best >= 0.82 && entityAnchor) || exact else { return nil }
            let allMembers = store.entries.values.filter { $0.id != entry.id && $0.clusterID == id }
            return (id, allMembers, 0.8 * best + 0.2 * centralSimilarity + (entityAnchor ? 0.08 : 0)
                    - min(0.12, age / (14 * 86400) * 0.12))
        }.sorted { a, b in a.2 == b.2 ? a.0.uuidString < b.0.uuidString : a.2 > b.2 }.prefix(12).map { $0 }
    }

    private func similarity(_ a: Entry, _ b: Entry) -> Double {
        guard a.encoderVersion == b.encoderVersion else { return 0 }
        return [
            StoryPairFeatures.cosine(a.profile.vector ?? [], b.profile.vector ?? []),
            StoryPairFeatures.cosine(a.profile.headlineVector ?? [], b.profile.headlineVector ?? []),
            StoryPairFeatures.cosine(a.profile.openingVector ?? [], b.profile.openingVector ?? [])
        ].max() ?? 0
    }

    private func representatives(of members: [Entry], near entry: Entry) -> [Entry] {
        // The original anchor prevents A~B and B~C from silently merging incompatible A and C.
        let ordered = members.sorted { a, b in
            let ad = a.date ?? a.receivedAt, bd = b.date ?? b.receivedAt
            return ad == bd ? a.id.uuidString < b.id.uuidString : ad < bd
        }
        let nearest = members.max { similarity(entry, $0) < similarity(entry, $1) }
        var seen: Set<UUID> = []
        return [ordered.first, nearest, ordered.last].compactMap { $0 }.filter { seen.insert($0.id).inserted }
    }

    func reviewPair(_ a: Entry, _ b: Entry, useApple: Bool = true) async -> StoryReview {
        let cacheKey = [a.fingerprint + a.encoderVersion, b.fingerprint + b.encoderVersion].sorted().joined(separator: ":") + (useApple ? ":review" : ":local")
        if let cached = pairCache[cacheKey] { return cached }
        let evidence = StoryEvidence.evaluate(a.profile, b.profile)
        let features = StoryPairFeatures.values(a.profile, b.profile)
        let eventConflict = features[7] > 0 || features[8] > 0 || features[9] > 0
        let withinBreakingWindow = abs((a.date ?? a.receivedAt).timeIntervalSince(b.date ?? b.receivedAt)) <= 3 * 86400
        let result: StoryReview
        if a.url != nil && a.url == b.url {
            result = StoryReview(relation: .sameEvent, score: 1, provider: "identity", reason: "same-url")
        } else if eventConflict {
            result = StoryReview(relation: .relatedDevelopment, score: 0, provider: "evidence-fallback", reason: "conflicting-event-evidence")
        } else if withinBreakingWindow && StoryEvidence.hasAnchoredIncidentEvidence(a.profile, b.profile) {
            // Preserve strong, concrete event evidence when the generative reviewer
            // mistakes different headlines about one live incident for separate events.
            result = StoryReview(relation: .sameEvent, score: 1, provider: "incident-evidence", reason: "shared-entity-incident-and-facts")
        } else if useSystemEmbeddings && injectedEncoder == nil
                    && ([a.language, b.language].compactMap { $0 }.contains { $0 != "en" }) {
            result = StoryReview(relation: .insufficientEvidence, score: 0, provider: "language-fallback", reason: "unsupported-language")
        } else {
            var apple: StoryReview?
            if useApple, let reviewer, remainingAppleReviews > 0 {
                remainingAppleReviews -= 1
                do { apple = try await reviewer(a.reviewText, b.reviewText) }
                catch { lastModelError = "Apple event review unavailable: \(error.localizedDescription)" }
            }
            if let apple {
                // A generated answer still needs supporting input evidence. Embeddings, when
                // available, are supplied by macOS NaturalLanguage, never by app-bundled assets.
                let comparable = a.encoderVersion == b.encoderVersion
                let supported = evidence.matches || (!a.profile.commentary && !b.profile.commentary
                    && ((comparable && max(features[0], features[1], features[2]) >= 0.65)
                        || (!a.profile.names.isDisjoint(with: b.profile.names) && features[3] >= 0.25)))
                // Apple can bridge different wording only when it cites exact
                // source text for both reports. Explicit event/person/sport
                // conflicts above remain hard vetoes.
                let groundedAppleMatch = apple.provider == "apple" && apple.matches
                    && apple.score >= 0.9 && apple.reason == "grounded-event-review"
                    && !a.profile.commentary && !b.profile.commentary
                result = apple.matches && !supported && !groundedAppleMatch
                    ? StoryReview(relation: .insufficientEvidence, score: 0, provider: "apple",
                                  reason: "generated-event-claim-lacks-independent-support")
                    : apple
            } else {
                result = StoryReview(relation: evidence.matches ? .sameEvent : .insufficientEvidence,
                                     score: evidence.matches ? 1 : 0, provider: "evidence-fallback", reason: evidence.reason)
            }
        }
        // Do not permanently cache temporary model failures or unavailable reviews.
        if result.provider == "apple" || result.provider == "identity" || reviewer == nil || !useApple {
            if pairCache.count >= 10000 { pairCache.removeAll(keepingCapacity: true) }
            pairCache[cacheKey] = result
        }
        return result
    }
}

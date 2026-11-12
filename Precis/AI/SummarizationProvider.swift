import Foundation
import FoundationModels
import NaturalLanguage

/// Independent, inspectable evidence for automatic story stacks. Semantic
/// similarity corroborates subject/action evidence; it cannot override conflicts.
enum StoryEvidence {
    struct Profile: Codable, Sendable {
        let title: Set<String>
        let body: Set<String>
        let names: Set<String>
        let mainPerson: Set<String>
        let sport: String?
        let development: String?
        var vector: [Double]?
        var places: Set<String> = []
        var commentary = false
        var headlineVector: [Double]?
        var openingVector: [Double]?
    }

    struct Evaluation: Sendable {
        let matches: Bool
        let reason: String
        let similarity: Double?
    }

    private static let weak: Set<String> = [
        "england", "australia", "britain", "british", "america", "usa", "uk", "us",
        "japan", "italy", "ireland", "scotland", "canada", "france", "germany",
        "team", "teams", "club", "clubs", "player", "players", "manager", "coach",
        "jockey", "head", "boss", "chief", "president", "minister", "government",
        "national", "international", "season", "year", "month", "week", "time",
        "set", "ready", "accept", "strike", "take", "become", "confirmed", "says",
        "said", "say", "thousand", "thousands", "million", "millions"
    ]

    static func normalized(_ text: String) -> String {
        var text = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: #"'s\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "'", with: "")
        // Whole phrases, not substring substitutions inside unrelated names.
        for (phrase, canonical) in [("vice president", "vicepresident"), ("vice-president", "vicepresident"), ("vp", "vicepresident"), ("manchester united", "manutd"), ("man utd", "manutd"), ("manchester city", "mancity"), ("man city", "mancity"), ("west indies", "westindies"), ("windies", "westindies"), ("south africa", "southafrica")] {
            text = text.replacingOccurrences(of: "\\b" + phrase + "\\b", with: canonical, options: .regularExpression)
        }
        return text
    }

    private static let countryTerms: Set<String> = {
        let locale = Locale(identifier: "en_US_POSIX")
        return Set(Locale.Region.isoRegions.flatMap { region in
            (locale.localizedString(forRegionCode: region.identifier) ?? "").lowercased()
                .split { !$0.isLetter }.map(String.init)
        })
    }()

    static func terms(_ text: String) -> Set<String> {
        let text = normalized(text)
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        // This matcher is English-only. Short tokens such as "dies" otherwise auto-detect as German.
        tagger.setLanguage(.english, range: text.startIndex..<text.endIndex)
        var words: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lemma,
                             options: [.omitWhitespace, .omitPunctuation]) { tag, range in
            words.append(tag?.rawValue.lowercased() ?? String(text[range]))
            return true
        }
        let aliases = ["scrap": "cancel", "expansion": "expand", "die": "death", "dies": "death", "died": "death", "dead": "death",
                       "comeback": "return", "threaten": "threat", "threatening": "threat",
                       "tumble": "fall", "plummet": "fall", "drop": "fall", "slump": "fall",
                       "investigation": "investigate", "inquiry": "investigate",
                       "resignation": "resign", "flee": "escape", "overrule": "overturn",
                       "relocation": "relocate", "impeachment": "impeach"]
        return Set(StoryMatching.storyTerms(words.joined(separator: " ")).map { aliases[$0] ?? $0 })
    }

    private static func entities(_ text: String) -> (names: Set<String>, firstPerson: Set<String>, places: Set<String>) {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var names: Set<String> = [], first: Set<String> = [], places: Set<String> = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
            let tokens = terms(String(text[range]))
            if tag == .placeName { places.formUnion(tokens); return true }
            guard tag == .personalName || tag == .organizationName else { return true }
            let namesOnly = tokens.subtracting(weak).subtracting(countryTerms)
            names.formUnion(namesOnly)
            // A quoted/reporting source is not necessarily the story's subject.
            let after = text[range.upperBound...].trimmingCharacters(in: .whitespaces).lowercased()
            let isReporter = after.hasPrefix("says ") || after.hasPrefix("said ")
            if tag == .personalName && first.isEmpty && !isReporter { first = namesOnly }
            return true
        }
        return (names, first, places)
    }

    private static func sport(_ article: ArticleListItem, text: String) -> String? {
        // Publisher article paths provide useful context without classifying
        // all articles from a general sports feed as the same sport.
        let path = article.link.flatMap(URL.init(string:))?.path.lowercased() ?? ""
        let sports = [("rugby-league", "rugby-league"), ("rugby-union", "rugby-union"),
                      ("horse-racing", "racing"), ("racing", "racing"), ("cricket", "cricket"),
                      ("football", "football"), ("tennis", "tennis"), ("golf", "golf"),
                      ("boxing", "boxing"), ("basketball", "basketball"), ("formula-1", "formula-1")]
        for (segment, sport) in sports where path.split(separator: "/").contains(Substring(segment)) { return sport }
        if text.contains("wheelchair rugby") { return "rugby-league" }
        return nil
    }

    static func conflictingSports(_ a: ArticleListItem, _ b: ArticleListItem) -> Bool {
        guard let first = sport(a, text: normalized(a.title + " " + a.articleBody)),
              let second = sport(b, text: normalized(b.title + " " + b.articleBody)) else { return false }
        return first != second
    }

    private static func development(title: String, text: String) -> String? {
        let t = terms(title)
        // Headline action takes precedence over causes and background in the lead.
        if t.contains("return") { return "return" }
        if t.contains("death") && !normalized(title).contains("death threat") { return "death" }
        if !t.isDisjoint(with: ["cancel", "postpone"]) { return "cancellation" }
        if t.contains("expand") { return "expansion" }
        if !t.isDisjoint(with: ["injury", "injure", "withdraw", "withdrawal"])
            || (normalized(title).contains("out of") && text.contains("injury")) { return "injury-withdrawal" }
        if !t.isDisjoint(with: ["share", "stock", "value"]) && t.contains("fall") { return "market-fall" }
        if t.contains("investigate") {
            if t.contains("fbi") || t.contains("police") { return "criminal-investigation" }
            if text.contains("law firm") || text.contains("independent investigation") { return "internal-investigation" }
            return "investigation"
        }
        if !t.isDisjoint(with: ["debut", "ipo", "valuation"]) && (text.contains("stock market") || text.contains("ipo")) { return "listing" }
        // The reported action outranks the cause (e.g. moving after threats).
        if t.contains("resign") { return "resignation" }
        if t.contains("escape") { return "escape" }
        if !t.isDisjoint(with: ["relocate", "move"]) && (text.contains("base") || text.contains("home")) { return "relocation" }
        if t.contains("overturn") { return "legal-overturn" }
        if t.contains("acquit") || normalized(title).contains("not guilty") { return "acquittal" }
        if t.contains("convict") || t.contains("guilty") { return "conviction" }
        if !t.isDisjoint(with: ["threat", "hoax"]) { return "threat" }
        if t.contains("police") && !t.isDisjoint(with: ["incident", "claim"]) { return "police-response" }
        if !t.isDisjoint(with: ["appoint", "appointment", "hire"])
            || (!t.isDisjoint(with: ["offer", "agreement"]) && (text.contains("coach") || text.contains("manager"))) { return "appointment" }
        if !t.isDisjoint(with: ["hammer", "thrash", "beat", "defeat", "win"]) { return "match-result" }
        if t.contains("fine") && (text.contains("court") || text.contains("regulator")) { return "legal-fine" }
        if t.contains("discharge") && (text.contains("patient") || text.contains("hospital")) { return "patient-discharge" }
        if t.contains("arrest") { return "arrest" }
        if !t.isDisjoint(with: ["charge", "accuse"]) || (t.contains("suspect") && t.contains("plot")) { return "criminal-accusation" }
        if t.contains("impeach") && !t.isDisjoint(with: ["block", "derail", "end"]) { return "impeachment-blocked" }
        if t.contains("ban") { return "ban" }
        if t.contains("summon") && text.contains("ambassador") { return "diplomatic-response" }
        if t.contains("blame") { return "attribution" }
        if t.contains("talk") && !t.contains("conference") { return "negotiations" }
        if !t.isDisjoint(with: ["vigil", "memorial"]) || (t.contains("march") && t.contains("silent") && t.contains("victim")) { return "commemoration" }
        if !t.isDisjoint(with: ["march", "protest"]) || (t.contains("strike") && (text.contains("worker") || text.contains("housing"))) { return "protest" }
        return nil
    }

    static func profile(_ article: ArticleListItem, embedding: NLEmbedding?) -> Profile {
        // articleBody uses already extracted/plain text. Do not fetch pages just
        // to classify a candidate; include a bounded opening when available.
        let lead = String(article.articleBody.prefix(900))
        let text = article.title + ". " + lead
        let normalizedText = normalized(text)
        let headlineEntities = entities(article.title)
        let allEntities = entities(text)
        return Profile(title: terms(article.title), body: terms(lead),
                       names: allEntities.names, mainPerson: headlineEntities.firstPerson,
                       sport: sport(article, text: normalizedText),
                       development: development(title: article.title, text: normalizedText),
                       vector: embedding?.vector(for: text), places: allEntities.places,
                       commentary: article.title.contains("?") || ["why ", "how ", "what we know", "what do we know"].contains(where: { normalized(article.title).hasPrefix($0) })
                           || normalized(article.title).contains(" unfazed "),
                       headlineVector: embedding?.vector(for: article.title),
                       openingVector: lead.isEmpty ? nil : embedding?.vector(for: lead))
    }

    private static func cosine(_ a: [Double]?, _ b: [Double]?) -> Double? {
        guard let a, let b, a.count == b.count, !a.isEmpty else { return nil }
        let dot = zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
        let length = sqrt(a.reduce(0) { $0 + $1 * $1 } * b.reduce(0) { $0 + $1 * $1 })
        return length > 0 ? dot / length : nil
    }

    static func evaluate(_ a: Profile, _ b: Profile) -> Evaluation {
        // Publishers provide very different lead lengths. Compare like with
        // like as well as the combined text, keeping all evidence vetoes.
        let similarity = [cosine(a.vector, b.vector), cosine(a.headlineVector, b.headlineVector),
                          cosine(a.openingVector, b.openingVector)].compactMap { $0 }.max()
        func result(_ match: Bool, _ reason: String) -> Evaluation {
            Evaluation(matches: match, reason: reason, similarity: similarity)
        }
        if a.commentary || b.commentary { return result(false, "analysis-or-reaction") }
        if let first = a.sport, let second = b.sport, first != second { return result(false, "different-sports") }
        if let first = a.development, let second = b.development, first != second { return result(false, "different-developments") }
        if !a.mainPerson.isEmpty && !b.mainPerson.isEmpty && a.mainPerson.isDisjoint(with: b.mainPerson) {
            return result(false, "different-main-people")
        }
        let common = a.title.intersection(b.title)
        let specific = common.subtracting(weak).subtracting(countryTerms)
        let sharedNames = a.names.intersection(b.names).intersection(a.title.union(b.title))
        let sameAction = a.development != nil && a.development == b.development
        func weight(_ term: String) -> Double {
            if weak.contains(term) || countryTerms.contains(term) { return 0.2 }
            if sharedNames.contains(term) { return 2.5 }
            return 1
        }
        let sharedWeight = common.reduce(0) { $0 + weight($1) }
        let totalWeight = min(a.title.reduce(0) { $0 + weight($1) }, b.title.reduce(0) { $0 + weight($1) })
        let coverage = totalWeight > 0 ? sharedWeight / totalWeight : 0
        let bodyOverlap = a.body.intersection(b.body).subtracting(weak).count
        // Never let a vector score alone create a stack. Require concrete
        // headline anchors plus independently compatible actions and subjects.
        if sameAction && specific.count >= 2 && coverage >= 0.45
            && (!sharedNames.isEmpty || specific.count >= 3)
            && ((similarity ?? 0) >= 0.60 || (coverage >= 0.75 && bodyOverlap >= 3)) {
            return result(true, "subject-action-corroborated")
        }
        if (sameAction || (a.development == nil && b.development == nil))
            && !sharedNames.isEmpty && specific.count >= 3 && coverage >= 0.60
            && ((similarity ?? 0) >= 0.70 || (coverage >= 0.85 && bodyOverlap >= 4)) {
            return result(true, "named-subject-and-strong-text")
        }
        // Headlines may identify a subject by role/country while the lead names
        // it explicitly. Use their combined evidence, not just headline overlap.
        let fullA = a.title.union(a.body), fullB = b.title.union(b.body)
        let facts = fullA.intersection(fullB).subtracting(weak).subtracting(countryTerms)
        let commonNames = a.names.intersection(b.names)
        let commonPlaces = a.places.intersection(b.places)
        let venues = commonPlaces.subtracting(countryTerms)
        let headlineToLead = a.title.intersection(fullB).union(b.title.intersection(fullA))
            .subtracting(weak).subtracting(countryTerms)
        if sameAction && venues.count >= 2 && commonPlaces.intersection(countryTerms).count >= 2
            && !headlineToLead.isEmpty && (similarity ?? 0) >= 0.60 {
            return result(true, "shared-participants-venue-and-action")
        }
        if sameAction && (similarity ?? 0) >= 0.60 && facts.count >= 3 && headlineToLead.count >= 2 {
            if !commonNames.isEmpty && (!specific.isEmpty || !commonPlaces.isEmpty) {
                return result(true, "named-subject-action-and-opening")
            }
            if !commonPlaces.isEmpty && (specific.count >= 2 || venues.count >= 2) {
                return result(true, "located-event-action-and-opening")
            }
        }
        return result(false, "insufficient-event-evidence")
    }
}

/// Legacy evidence-only matcher retained as a regression oracle. Production stacks use
/// StoryClusterService, which persists memberships and combines local models with Apple review.
actor StorySimilarityService {
    enum ReviewPath: String, Sendable { case notRun, cached, evidence }
    private var profiles: [String: StoryEvidence.Profile] = [:]
    private var candidates: [String: StoryMatching.CandidateFeatures] = [:]
    private var decisions: [String: StoryEvidence.Evaluation] = [:]
    private let embedding = NLEmbedding.sentenceEmbedding(for: .english)
    private(set) var lastReviewPath: ReviewPath = .notRun
    private(set) var lastReviewError: String?
    private(set) var lastReviewReason = ""
    private(set) var lastSimilarity: Double?

    private func key(_ article: ArticleListItem) -> String {
        article.title + "\u{0}" + String(article.articleBody.prefix(900)) + "\u{0}" + (article.link ?? "")
    }

    private func profile(_ article: ArticleListItem, key: String) -> StoryEvidence.Profile {
        if let cached = profiles[key] { return cached }
        let profile = StoryEvidence.profile(article, embedding: embedding)
        profiles[key] = profile
        return profile
    }

    /// Lemmatise on this actor rather than blocking the list's main actor.
    func candidateFeatures(for articles: [ArticleListItem]) -> [UUID: StoryMatching.CandidateFeatures] {
        var result: [UUID: StoryMatching.CandidateFeatures] = [:]
        for article in articles {
            guard !Task.isCancelled else { return result }
            let contentKey = key(article)
            let features = candidates[contentKey] ?? StoryMatching.CandidateFeatures(article)
            candidates[contentKey] = features
            result[article.id] = features
        }
        return result
    }

    func areSameStory(_ first: ArticleListItem, _ second: ArticleListItem) -> Bool {
        let firstKey = key(first), secondKey = key(second)
        let pairKey = [firstKey, secondKey].sorted().joined(separator: "\u{1}")
        let evaluation: StoryEvidence.Evaluation
        if let cached = decisions[pairKey] {
            lastReviewPath = .cached
            evaluation = cached
        } else {
            lastReviewPath = .evidence
            evaluation = StoryEvidence.evaluate(profile(first, key: firstKey), profile(second, key: secondKey))
            decisions[pairKey] = evaluation
        }
        lastReviewReason = evaluation.reason
        lastSimilarity = evaluation.similarity
        return evaluation.matches
    }
}

public protocol SummarizationProvider {
    var providerName: String { get }
    func summarize(_ text: String) async throws -> Summary
    func summarize(article: Article) async throws -> Summary
    func summarizeDigest(
        _ text: String,
        onProgress: (@MainActor @Sendable (Double) -> Void)?
    ) async throws -> Summary
    func availability() -> Bool
}

public extension SummarizationProvider {
    func summarize(article: Article) async throws -> Summary {
        let text = article.extractedContent ?? article.rawContent ?? article.title
        return try await summarize(text)
    }

    /// Digests that don't need to report progress.
    func summarizeDigest(_ text: String) async throws -> Summary {
        try await summarizeDigest(text, onProgress: nil)
    }
}

/// Picks the summarizer for a run: the on-device model when Apple Intelligence
/// is available on the machine, the local heuristic when it isn't.
public enum SummarizationProviderFactory {
    public static func makeDefault() -> SummarizationProvider {
        let onDevice = AppleIntelligenceSummarizationProvider()
        return onDevice.availability() ? onDevice : LocalHeuristicSummarizationProvider()
    }
}

/// On-device AI summarization using Apple's Foundation Models framework.
/// Falls back to the local heuristic if the model is unavailable or fails.
public final class AppleIntelligenceSummarizationProvider: SummarizationProvider {
    public let providerName = "Apple Intelligence"

    public init() {}

    public func availability() -> Bool {
        SystemLanguageModel.default.isAvailable
    }

    public func summarize(_ text: String) async throws -> Summary {
        let cleaned = HeuristicSummarization.clean(text)

        guard !cleaned.isEmpty else {
            return HeuristicSummarization.emptySummary(providerName)
        }

        do {
            return try await summarizeWithFoundationModels(cleaned)
        } catch {
            // Model unavailable mid-run — the heuristic still answers.
            return HeuristicSummarization.summarize(cleaned)
        }
    }

    public func summarizeDigest(
        _ text: String,
        onProgress: (@MainActor @Sendable (Double) -> Void)? = nil
    ) async throws -> Summary {
        let cleaned = HeuristicSummarization.clean(text)

        guard !cleaned.isEmpty else {
            return HeuristicSummarization.emptySummary(providerName)
        }

        do {
            return try await summarizeDigestWithFoundationModels(cleaned, onProgress: onProgress)
        } catch {
            await onProgress?(1)
            return HeuristicSummarization.summarizeDigest(cleaned)
        }
    }

    // MARK: - Foundation Models (real AI)

    private func summarizeWithFoundationModels(_ text: String) async throws -> Summary {
        let truncated = text.count > 2000 ? String(text.prefix(2000)) + "..." : text

        // Resolve the model here, not in init(): init runs synchronously on
        // the caller's actor (the main actor at launch), and the first touch of
        // SystemLanguageModel loads large system frameworks on that thread —
        // on main that produced a 1-2s beachball on first interaction. This
        // method is nonisolated async, so it runs off the main actor.
        let session = LanguageModelSession(model: SystemLanguageModel.default)

        let prompt = """
        Summarize this article in exactly 1-2 concise sentences. \
        Focus on the main point and key facts. \
        Be neutral and factual. \
        Do not use phrases like "This article" or "The article discusses".

        Article:
        \(truncated)
        """

        let response = try await session.respond(to: prompt)
        let shortText = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !shortText.isEmpty else {
            throw SummarizationError.emptyResponse
        }

        // Generate bullet points
        let bulletPrompt = """
        Extract 2-3 key bullet points from this article. \
        Each bullet should be a single sentence stating a key fact or takeaway. \
        Return only the bullet points, one per line, without bullet characters.

        Article:
        \(truncated)
        """

        let bulletResponse = try await session.respond(to: bulletPrompt)
        let bulletPoints = HeuristicSummarization.bulletLines(from: bulletResponse.content)

        return Summary(
            articleID: UUID(),
            shortText: shortText,
            bulletPoints: Array(bulletPoints.prefix(3)),
            generatedBy: "Apple Intelligence (on-device)"
        )
    }

    private func summarizeDigestWithFoundationModels(
        _ text: String,
        onProgress: (@MainActor @Sendable (Double) -> Void)?
    ) async throws -> Summary {
        let session = LanguageModelSession(model: SystemLanguageModel.default)

        let prompt = """
        Write one concise paragraph synthesizing the important themes and facts across all of these article summaries. Consider the entire list, not just its opening entries. Be neutral and factual.

        Articles:
        \(text)
        """

        await onProgress?(0.05)
        let response = try await session.respond(to: prompt)
        let shortText = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !shortText.isEmpty else {
            throw SummarizationError.emptyResponse
        }
        await onProgress?(0.55)

        let bulletPrompt = """
        Extract up to 8 distinct key takeaways from across the entire list of article summaries below. Spread the takeaways across different articles where possible. Each should be one concise sentence. Return only one takeaway per line, without bullet characters.

        Articles:
        \(text)
        """

        let bulletResponse = try await session.respond(to: bulletPrompt)
        await onProgress?(0.95)

        return Summary(
            articleID: UUID(),
            shortText: shortText,
            bulletPoints: Array(HeuristicSummarization.bulletLines(from: bulletResponse.content).prefix(8)),
            generatedBy: "Apple Intelligence (on-device)"
        )
    }
}

/// Fast local summaries built from the article text — used on machines without
/// Apple Intelligence, and as the fallback when the on-device model fails.
public final class LocalHeuristicSummarizationProvider: SummarizationProvider {
    public let providerName = "Precis (heuristic)"

    public init() {}

    public func availability() -> Bool {
        return true
    }

    public func summarize(_ text: String) async throws -> Summary {
        let cleaned = HeuristicSummarization.clean(text)

        guard !cleaned.isEmpty else {
            return HeuristicSummarization.emptySummary(providerName)
        }

        return HeuristicSummarization.summarize(cleaned)
    }

    public func summarizeDigest(
        _ text: String,
        onProgress: (@MainActor @Sendable (Double) -> Void)? = nil
    ) async throws -> Summary {
        let cleaned = HeuristicSummarization.clean(text)
        await onProgress?(1)

        guard !cleaned.isEmpty else {
            return HeuristicSummarization.emptySummary(providerName)
        }

        return HeuristicSummarization.summarizeDigest(cleaned)
    }
}

/// Deterministic, model-free summarization.
enum HeuristicSummarization {
    static func clean(_ text: String) -> String {
        // Decode named and numeric entities before summarizing: entity codes
        // that reached a prompt previously showed up verbatim in the summary.
        ArticleHTMLSanitizer.plainText(fromHTML: text)
    }

    static func emptySummary(_ generatedBy: String) -> Summary {
        Summary(
            articleID: UUID(),
            shortText: "No article content available to summarize.",
            bulletPoints: [],
            generatedBy: generatedBy
        )
    }

    static func summarize(_ text: String) -> Summary {
        let sentences = sentences(from: text)

        let paragraph: String
        switch sentences.count {
        case 0: paragraph = String(text.prefix(200))
        case 1: paragraph = sentences[0]
        default: paragraph = sentences[0...1].joined(separator: " ")
        }

        // Bullets are taken from the sentences the paragraph skipped, so an
        // article summary never states the same sentence twice.
        let bullets = sentences.dropFirst(min(sentences.count, 2)).prefix(3)

        return Summary(
            articleID: UUID(),
            shortText: paragraph,
            bulletPoints: Array(bullets),
            generatedBy: "Precis (heuristic)"
        )
    }

    static func summarizeDigest(_ text: String) -> Summary {
        let headlines = lines(from: text).map { line in
            sentences(from: line).first ?? line
        }

        guard !headlines.isEmpty else {
            return emptySummary("Precis (heuristic)")
        }

        let paragraphIndexes = representativeIndexes(count: headlines.count, maximum: 3)
        let paragraph = paragraphIndexes.map { headlines[$0] }.joined(separator: " ")

        // The bullets come from the articles the paragraph does not quote, so
        // the card reads as a digest instead of printing itself twice.
        let bullets = representativeIndexes(count: headlines.count, maximum: 6)
            .filter { !paragraphIndexes.contains($0) }
            .map { headlines[$0] }

        return Summary(
            articleID: UUID(),
            shortText: paragraph.isEmpty ? String(text.prefix(200)) : paragraph,
            bulletPoints: bullets,
            generatedBy: "Precis (heuristic)"
        )
    }

    /// One trimmed, marker-free line per article.
    static func lines(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { stripBulletMarkers($0) }
            .filter { !$0.isEmpty }
    }

    /// Views add their own bullet glyphs, so authored markers are stripped —
    /// otherwise a digest line reaches the page as "• • Headline".
    static func stripBulletMarkers(_ text: String) -> String {
        text
            .replacingOccurrences(of: "^[\\s\\-–—•*·]+", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func bulletLines(from response: String) -> [String] {
        response
            .components(separatedBy: .newlines)
            .map { stripBulletMarkers($0) }
            .filter { !$0.isEmpty }
    }

    static func representativeIndexes(count: Int, maximum: Int) -> [Int] {
        guard count > 0 else { return [] }
        guard count > maximum else { return Array(0..<count) }
        return (0..<maximum).map { $0 * (count - 1) / (maximum - 1) }
    }

    /// Splits on sentence terminators, keeping the terminator with its sentence
    /// so joined paragraphs read properly.
    static func sentences(from text: String) -> [String] {
        var sentences: [String] = []
        var current = ""

        for character in text {
            current.append(character)
            guard character == "." || character == "!" || character == "?" else { continue }
            let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if sentence.count > 20 {
                sentences.append(sentence)
            }
            current = ""
        }

        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if tail.count > 20 {
            sentences.append(tail)
        }

        return sentences
    }
}

/// The "Today's Precis" card: a heading, the synthesized paragraph, and then
/// only the takeaways the paragraph does not already state.
public enum PrecisDigest {
    public static func cardText(articleCount: Int, paragraph: String, bullets: [String]) -> String {
        var text = "**\(articleCount) articles from the last 24 hours:**"

        let paragraph = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        if !paragraph.isEmpty {
            text += "\n\n" + paragraph
        }

        let takeaways = bullets
            .map { stripLeadingBullet($0) }
            .filter { !$0.isEmpty && !paragraph.localizedCaseInsensitiveContains($0) }

        if !takeaways.isEmpty {
            text += "\n\n" + takeaways.map { "• \($0)" }.joined(separator: "\n")
        }

        return text
    }

    private static func stripLeadingBullet(_ text: String) -> String {
        HeuristicSummarization.stripBulletMarkers(text)
    }
}

enum SummarizationError: Error {
    case emptyResponse
}

public final class CloudFallbackSummarizationProvider: SummarizationProvider {
    public let providerName = "Cloud Fallback"

    public init() {}

    public func availability() -> Bool {
        return false
    }

    public func summarize(_ text: String) async throws -> Summary {
        return try await LocalHeuristicSummarizationProvider().summarize(text)
    }

    public func summarizeDigest(
        _ text: String,
        onProgress: (@MainActor @Sendable (Double) -> Void)? = nil
    ) async throws -> Summary {
        return try await LocalHeuristicSummarizationProvider().summarizeDigest(text, onProgress: onProgress)
    }
}

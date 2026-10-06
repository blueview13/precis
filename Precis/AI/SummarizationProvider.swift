import Foundation
import FoundationModels

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

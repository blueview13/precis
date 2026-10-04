import Foundation
import FoundationModels

public protocol SummarizationProvider {
    var providerName: String { get }
    func summarize(_ text: String) async throws -> Summary
    func summarize(article: Article) async throws -> Summary
    func availability() -> Bool
}

/// On-device AI summarization using Apple's Foundation Models framework.
/// Falls back to a smart heuristic if FoundationModels is unavailable.
public final class AppleIntelligenceSummarizationProvider: SummarizationProvider {
    public let providerName = "Apple Intelligence"

    public init() {}

    public func summarize(_ text: String) async throws -> Summary {
        let cleaned = Self.clean(text)

        guard !cleaned.isEmpty else {
            return Summary(
                articleID: UUID(),
                shortText: "No article content available to summarize.",
                bulletPoints: [],
                generatedBy: providerName
            )
        }

        // Try FoundationModels first; fall back to heuristic on failure
        do {
            return try await summarizeWithFoundationModels(cleaned)
        } catch {
            // FoundationModels unavailable — use smart heuristic fallback
            return summarizeWithHeuristic(cleaned)
        }
    }

    public func summarizeDigest(
        _ text: String,
        onProgress: (@MainActor @Sendable (Double) -> Void)? = nil
    ) async throws -> Summary {
        let cleaned = Self.clean(text)

        guard !cleaned.isEmpty else {
            return Summary(
                articleID: UUID(),
                shortText: "No article content available to summarize.",
                bulletPoints: [],
                generatedBy: providerName
            )
        }

        do {
            return try await summarizeDigestWithFoundationModels(cleaned, onProgress: onProgress)
        } catch {
            return summarizeDigestWithHeuristic(cleaned)
        }
    }

    public func summarize(article: Article) async throws -> Summary {
        let text = article.extractedContent ?? article.rawContent ?? article.title
        return try await summarize(text)
    }

    public func availability() -> Bool {
        return true
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
        let bulletLines = bulletResponse.content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "^[-•*]\\s*", with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }
        let bulletPoints = Array(bulletLines.prefix(3))

        return Summary(
            articleID: UUID(),
            shortText: shortText,
            bulletPoints: bulletPoints,
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
        let bulletPoints = bulletResponse.content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "^[-•*]\\s*", with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }

        return Summary(
            articleID: UUID(),
            shortText: shortText,
            bulletPoints: Array(bulletPoints.prefix(8)),
            generatedBy: "Apple Intelligence (on-device)"
        )
    }

    // MARK: - Heuristic Fallback (no AI model needed)

    private func summarizeWithHeuristic(_ text: String) -> Summary {
        let sentences = Self.sentences(from: text)

        // Build summary from the most informative sentences
        let shortText: String
        if sentences.count >= 2 {
            shortText = [sentences[0], sentences[1]].joined(separator: " ")
        } else if let first = sentences.first {
            shortText = first
        } else {
            shortText = String(text.prefix(200))
        }

        // Extract key facts as bullet points
        let bulletPoints = sentences.prefix(3).map { String($0) }

        return Summary(
            articleID: UUID(),
            shortText: shortText,
            bulletPoints: bulletPoints,
            generatedBy: "Precis (heuristic)"
        )
    }

    private func summarizeDigestWithHeuristic(_ text: String) -> Summary {
        let articleLines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let articleSentences = articleLines.map { line in
            Self.sentences(from: line).first ?? line
        }
        let bulletIndexes = Self.representativeIndexes(count: articleSentences.count, maximum: 8)
        let bulletPoints = bulletIndexes.map { articleSentences[$0] }
        let representativeIndexes = Self.representativeIndexes(count: articleSentences.count, maximum: 4)
        let paragraphSentences = representativeIndexes.map { articleSentences[$0] }
        let shortText = paragraphSentences.joined(separator: " ")

        return Summary(
            articleID: UUID(),
            shortText: shortText.isEmpty ? String(text.prefix(200)) : shortText,
            bulletPoints: bulletPoints,
            generatedBy: "Precis (heuristic)"
        )
    }

    private static func representativeIndexes(count: Int, maximum: Int) -> [Int] {
        guard count > 0 else { return [] }
        guard count > maximum else { return Array(0..<count) }
        return (0..<maximum).map { $0 * (count - 1) / (maximum - 1) }
    }

    // MARK: - Utilities

    private static func clean(_ text: String) -> String {
        // Full entity decoding (named AND numeric) via the shared helper. The
        // hand-rolled list here previously missed `&#8216;`-style codes, which
        // the model then echoed back verbatim into the generated summaries.
        ArticleHTMLSanitizer.plainText(fromHTML: text)
    }

    private static func sentences(from text: String) -> [String] {
        let split = text.split(whereSeparator: { $0 == "." || $0 == "!" || $0 == "?" })
        return split
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 20 }
    }
}

enum SummarizationError: Error {
    case emptyResponse
}

public final class CloudFallbackSummarizationProvider: SummarizationProvider {
    public let providerName = "Cloud Fallback"

    public init() {}

    public func summarize(_ text: String) async throws -> Summary {
        return try await AppleIntelligenceSummarizationProvider().summarize(text)
    }

    public func summarize(article: Article) async throws -> Summary {
        let text = article.extractedContent ?? article.rawContent ?? article.title
        return try await summarize(text)
    }

    public func availability() -> Bool {
        false
    }
}

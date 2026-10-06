import Foundation

public protocol SummarizationProvider {
    var providerName: String { get }
    func summarize(_ text: String) async throws -> Summary
    func summarize(article: Article) async throws -> Summary
    func availability() -> Bool
}

/// Fast local article summaries built from the extracted text.
public final class LocalHeuristicSummarizationProvider: SummarizationProvider {
    public let providerName = "Precis (heuristic)"

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

        return summarizeWithHeuristic(cleaned)
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

        let summary = summarizeDigestWithHeuristic(cleaned)
        await onProgress?(1)
        return summary
    }

    public func summarize(article: Article) async throws -> Summary {
        let text = article.extractedContent ?? article.rawContent ?? article.title
        return try await summarize(text)
    }

    public func availability() -> Bool {
        return true
    }

    // MARK: - Heuristic summaries

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
        // Decode entities before making summaries from article text.
        ArticleHTMLSanitizer.plainText(fromHTML: text)
    }

    private static func sentences(from text: String) -> [String] {
        let split = text.split(whereSeparator: { $0 == "." || $0 == "!" || $0 == "?" })
        return split
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 20 }
    }
}

public final class CloudFallbackSummarizationProvider: SummarizationProvider {
    public let providerName = "Cloud Fallback"

    public init() {}

    public func summarize(_ text: String) async throws -> Summary {
        return try await LocalHeuristicSummarizationProvider().summarize(text)
    }

    public func summarize(article: Article) async throws -> Summary {
        let text = article.extractedContent ?? article.rawContent ?? article.title
        return try await summarize(text)
    }

    public func availability() -> Bool {
        false
    }
}

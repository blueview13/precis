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
    private let model: SystemLanguageModel

    public init() {
        self.model = SystemLanguageModel.default
    }

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

        let session = LanguageModelSession(model: model)

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

    // MARK: - Utilities

    private static func clean(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized
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

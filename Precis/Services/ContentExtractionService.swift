import Foundation

public struct ExtractedArticleContent {
    public let title: String
    public let normalizedText: String
    public let excerpt: String
    public let wordCount: Int

    public init(title: String, normalizedText: String, excerpt: String, wordCount: Int) {
        self.title = title
        self.normalizedText = normalizedText
        self.excerpt = excerpt
        self.wordCount = wordCount
    }
}

public protocol ContentExtractionServiceProtocol {
    func extract(from rawText: String, title: String) -> ExtractedArticleContent
}

public final class ContentExtractionService: ContentExtractionServiceProtocol {
    public init() {}

    public func extract(from rawText: String, title: String) -> ExtractedArticleContent {
        let cleaned = rawText
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let excerpt = String(cleaned.prefix(260))
        let words = cleaned.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        return ExtractedArticleContent(
            title: title,
            normalizedText: cleaned,
            excerpt: excerpt,
            wordCount: words.count
        )
    }
}

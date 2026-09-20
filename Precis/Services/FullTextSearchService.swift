import Foundation

public protocol FullTextSearchServiceProtocol {
    func search(_ query: String, in articles: [Article]) -> [Article]
}

public final class FullTextSearchService: FullTextSearchServiceProtocol {
    public init() {}

    public func search(_ query: String, in articles: [Article]) -> [Article] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return articles }

        return articles.filter { article in
            let haystack = [
                article.title,
                article.rawContent ?? "",
                article.extractedContent ?? "",
                article.author ?? ""
            ].joined(separator: " ").lowercased()
            return haystack.contains(normalized)
        }
    }
}

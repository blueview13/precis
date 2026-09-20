import Foundation

public protocol SummarizationProvider {
    var providerName: String { get }
    func summarize(_ text: String) async throws -> Summary
    func summarize(article: Article) async throws -> Summary
    func availability() -> Bool
}

public final class AppleIntelligenceSummarizationProvider: SummarizationProvider {
    public let providerName = "Apple Intelligence"

    public init() {}

    public func summarize(_ text: String) async throws -> Summary {
        let fallback = Summary(
            articleID: UUID(),
            shortText: "Summary generated locally by Apple Intelligence.",
            bulletPoints: [
                "The article text was processed on-device.",
                "The summary remains private to the device by default."
            ],
            generatedBy: providerName
        )
        return fallback
    }

    public func summarize(article: Article) async throws -> Summary {
        let text = article.extractedContent ?? article.rawContent ?? ""
        return try await summarize(text)
    }

    public func availability() -> Bool {
        true
    }
}

public final class CloudFallbackSummarizationProvider: SummarizationProvider {
    public let providerName = "Cloud Fallback"

    public init() {}

    public func summarize(_ text: String) async throws -> Summary {
        Summary(
            articleID: UUID(),
            shortText: "Cloud fallback is available only when the user explicitly opts in.",
            generatedBy: providerName
        )
    }

    public func summarize(article: Article) async throws -> Summary {
        try await summarize(article.extractedContent ?? article.rawContent ?? "")
    }

    public func availability() -> Bool {
        false
    }
}

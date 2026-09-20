import Foundation

public protocol AIProvider {
    var providerName: String { get }
    func summarize(_ text: String) async throws -> Summary
    func availability() -> Bool
}

public final class OnDeviceAppleIntelligenceProvider: AIProvider {
    public let providerName = "Apple Intelligence"

    public init() {}

    public func summarize(_ text: String) async throws -> Summary {
        let articleID = UUID()
        return Summary(
            articleID: articleID,
            shortText: "Summary unavailable until model integration is wired up.",
            generatedBy: providerName
        )
    }

    public func availability() -> Bool {
        true
    }
}

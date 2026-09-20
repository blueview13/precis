import AppIntents
import Foundation

@available(macOS 26.0, *)
struct SummarizeUnreadFeedIntent: AppIntent {
    static let title: LocalizedStringResource = "Summarize unread items from a feed"
    static let description = IntentDescription("Summarize unread articles from a specific feed or folder.")

    @Parameter(title: "Feed or folder")
    var target: String

    func perform() async throws -> some IntentResult {
        .result(value: "Summary queue started for \(target)")
    }
}

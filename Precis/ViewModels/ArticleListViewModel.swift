import Foundation
import SwiftUI

@MainActor
public final class ArticleListViewModel: ObservableObject {
    @Published public var items: [ArticleListItem] = [
        ArticleListItem(
            title: "The quiet power of good reading interfaces",
            feedTitle: "The Verge",
            publishedDate: Date().addingTimeInterval(-180),
            isRead: false,
            isStarred: true,
            snippet: "Quiet interfaces don’t subtract from the reading experience — they make it easier to trust the words in front of you."
        ),
        ArticleListItem(
            title: "How Apple Intelligence changes local summaries",
            feedTitle: "MacStories",
            publishedDate: Date().addingTimeInterval(-1260),
            isRead: false,
            isStarred: false,
            snippet: "Local inference is quietly becoming a major part of the reading experience on Apple devices."
        ),
        ArticleListItem(
            title: "Why RSS still feels essential on a focused machine",
            feedTitle: "Signals",
            publishedDate: Date().addingTimeInterval(-3600),
            isRead: true,
            isStarred: false,
            snippet: "The core appeal of RSS is not novelty; it is control, speed, and intentional reading."
        )
    ]

    public init() {}

    public func toggleRead(_ item: ArticleListItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].isRead.toggle()
        }
    }

    public func toggleStarred(_ item: ArticleListItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].isStarred.toggle()
        }
    }
}

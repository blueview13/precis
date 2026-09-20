import Foundation

public protocol SmartFolderServiceProtocol {
    func matches(_ article: Article, folder: SmartFolder) -> Bool
}

public final class SmartFolderService: SmartFolderServiceProtocol {
    public init() {}

    public func matches(_ article: Article, folder: SmartFolder) -> Bool {
        guard !folder.criteria.isEmpty else { return true }

        let results = folder.criteria.map { criterion in
            switch criterion.field {
            case .title:
                return article.title.lowercased().contains(criterion.value.lowercased())
            case .content:
                return (article.extractedContent ?? article.rawContent ?? "").lowercased().contains(criterion.value.lowercased())
            case .feed:
                return article.feedID.uuidString.lowercased().contains(criterion.value.lowercased())
            case .ageDays:
                guard let publishedDate = article.publishedDate else { return false }
                let ageDays = Calendar.current.dateComponents([.day], from: publishedDate, to: Date()).day ?? 0
                let maxAgeDays = Int(criterion.value) ?? 0
                return ageDays <= maxAgeDays
            case .readState:
                return (article.isRead && criterion.value.lowercased() == "read") || (!article.isRead && criterion.value.lowercased() == "unread")
            }
        }

        switch folder.operatorType {
        case .all:
            return results.allSatisfy { $0 }
        case .any:
            return results.contains(true)
        }
    }
}

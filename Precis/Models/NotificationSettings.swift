import Foundation

public enum NotificationGranularity: String, Codable, CaseIterable {
    case sync
    case feed
    case article

    public var displayName: String {
        switch self {
        case .sync:
            return "One notification per sync"
        case .feed:
            return "One notification per feed"
        case .article:
            return "Per-article alerts"
        }
    }
}

public struct NotificationSettings: Codable {
    public var granularity: NotificationGranularity
    public var dockBadgeEnabled: Bool
    public var mustSeeFeedIDs: [UUID]

    public init(granularity: NotificationGranularity = .sync, dockBadgeEnabled: Bool = true, mustSeeFeedIDs: [UUID] = []) {
        self.granularity = granularity
        self.dockBadgeEnabled = dockBadgeEnabled
        self.mustSeeFeedIDs = mustSeeFeedIDs
    }
}

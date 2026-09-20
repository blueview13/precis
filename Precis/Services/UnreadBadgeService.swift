import Foundation

public protocol UnreadBadgeServiceProtocol {
    func badgeCount(for unreadCount: Int) -> Int
    func notificationMode() -> String
}

public final class UnreadBadgeService: UnreadBadgeServiceProtocol {
    public init() {}

    public func badgeCount(for unreadCount: Int) -> Int {
        max(unreadCount, 0)
    }

    public func notificationMode() -> String {
        "one notification per sync"
    }
}

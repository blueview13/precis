import Foundation
import UserNotifications

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

@MainActor
public enum NewArticleNotificationService {
    public static func requestAuthorization() async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return try await center.requestAuthorization(options: [.alert, .sound])
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    public static func sendNewArticlesNotification(count: Int, feedNames: [String]) async throws {
        guard count > 0 else { return }

        let uniqueFeedNames = Array(Set(feedNames)).sorted()
        let content = UNMutableNotificationContent()
        content.title = count == 1 ? "1 New Article" : "\(count) New Articles"
        if uniqueFeedNames.count == 1, let feedName = uniqueFeedNames.first {
            content.body = "New stories from \(feedName)."
        } else if uniqueFeedNames.count > 1 {
            content.body = "New stories from \(uniqueFeedNames.count) feeds."
        } else {
            content.body = "Your feeds have new stories."
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "Precis.NewArticles.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try await UNUserNotificationCenter.current().add(request)
    }
}

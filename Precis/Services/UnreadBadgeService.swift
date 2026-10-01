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
    public static func settingsGuidance() async -> String? {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .denied {
            return "Allow notifications for Precis in System Settings to receive alerts."
        }
        if settings.showPreviewsSetting == .never {
            return "macOS is hiding notification details. Set Show Previews to Always in System Settings > Notifications > Precis to see feed names."
        }
        return nil
    }

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

        let uniqueFeedNames = Array(Set(feedNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        let content = UNMutableNotificationContent()
        if uniqueFeedNames.isEmpty {
            content.title = "New articles in your feeds"
        } else if uniqueFeedNames.count == 1, let feedName = uniqueFeedNames.first {
            content.title = "New articles from \(feedName)"
        } else if uniqueFeedNames.count == 2 {
            content.title = "New articles from \(uniqueFeedNames[0]) and \(uniqueFeedNames[1])"
        } else {
            let displayedFeedNames = uniqueFeedNames.prefix(2).joined(separator: ", ")
            let remainingFeedCount = uniqueFeedNames.count - 2
            content.title = "New articles from \(displayedFeedNames), and \(remainingFeedCount) more feeds"
        }
        content.body = count == 1 ? "1 new article arrived." : "\(count) new articles arrived."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "Precis.NewArticles.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try await UNUserNotificationCenter.current().add(request)
    }
}

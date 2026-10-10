import Foundation
import Security
import SwiftData

public struct FeedbinCredentials: Equatable, Sendable {
    public var username: String
    public var password: String
    public init(username: String, password: String) {
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        self.password = password
    }
}

public enum FeedbinError: LocalizedError {
    case invalidCredentials, feedNotFound, requestFailed(Int), invalidResponse
    case invalidOldReaderCredentials, oldReaderRequestFailed(Int), oldReaderInvalidResponse
    public var errorDescription: String? {
        switch self {
        case .invalidCredentials: "Feedbin credentials were rejected. Check your email and password."
        case .feedNotFound: "Feedbin couldn't find a feed at that address. Check the URL or paste the direct RSS/Atom feed link."
        case .requestFailed(let code): "Feedbin returned an error (HTTP \(code))."
        case .invalidResponse: "Feedbin returned an unreadable response."
        case .invalidOldReaderCredentials: "The Old Reader rejected these credentials. Check the email and account password."
        case .oldReaderRequestFailed(let code): "The Old Reader returned an error (HTTP \(code))."
        case .oldReaderInvalidResponse: "The Old Reader returned an unreadable response."
        }
    }
}

/// Credentials stay in the macOS Keychain; the API client never writes them to preferences.
public enum FeedbinCredentialStore {
    private static let service = "com.precis.feedbin"
    private static let account = "credentials"
    private actor SessionCache {
        static let shared = SessionCache()
        private var credentials: FeedbinCredentials?
        private var pendingLoad: Task<FeedbinCredentials?, Never>?
        func get() async -> FeedbinCredentials? {
            if let credentials { return credentials }
            if let pendingLoad { return await pendingLoad.value }
            let task = Task.detached(priority: .userInitiated) { loadSync() }
            pendingLoad = task
            let result = await task.value
            credentials = result
            pendingLoad = nil
            return result
        }
        func set(_ value: FeedbinCredentials?) {
            credentials = value
            pendingLoad = nil
        }
    }
    public static func load() async -> FeedbinCredentials? {
        await SessionCache.shared.get()
    }
    private static func loadSync() -> FeedbinCredentials? {
        guard let data = read(account: account),
              let pair = try? JSONDecoder().decode(FeedbinCredentialsPayload.self, from: data) else { return nil }
        return FeedbinCredentials(username: pair.username, password: pair.password)
    }
    public static func save(_ credentials: FeedbinCredentials) async throws {
        let payload = try JSONEncoder().encode(FeedbinCredentialsPayload(username: credentials.username, password: credentials.password))
        try await Task.detached(priority: .userInitiated) {
            try write(payload, account: account)
        }.value
        await SessionCache.shared.set(credentials)
    }
    public static func delete() async {
        await Task.detached(priority: .userInitiated) { deleteSync(account: account) }.value
        await SessionCache.shared.set(nil)
    }
    private struct FeedbinCredentialsPayload: Codable, Sendable {
        let username: String
        let password: String
    }
    private static func read(account: String) -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne] as CFDictionary, &result)
        return status == errSecSuccess ? result as? Data : nil
    }
    private static func write(_ data: Data, account: String) throws {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus)) }
        var item = query
        item[kSecValueData] = data
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
    private static func deleteSync(account: String) {
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary)
    }
}

@MainActor public final class FeedbinService {
    private let credentials: FeedbinCredentials
    private let session: URLSession
    private let base = URL(string: "https://api.feedbin.com/v2")!

    public init(credentials: FeedbinCredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    private struct Subscription: Decodable {
        let id: Int
        let feed_id: Int
        let title: String
        let feed_url: String
    }
    private struct Tagging: Decodable {
        let id: Int
        let feed_id: Int
        let name: String
    }

    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = method
        let token = Data("\(credentials.username):\(credentials.password)".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FeedbinError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw FeedbinError.invalidCredentials }
        if http.statusCode == 404 && method == "POST" && path == "subscriptions.json" { throw FeedbinError.feedNotFound }
        guard (200..<300).contains(http.statusCode) else { throw FeedbinError.requestFailed(http.statusCode) }
        return (data, http)
    }

    public func addSubscription(url: URL) async throws -> (subscriptionID: Int, feedID: Int) {
        let (data, _) = try await request("subscriptions.json", method: "POST", body: ["feed_url": url.absoluteString])
        guard let result = try? JSONDecoder().decode(Subscription.self, from: data) else { throw FeedbinError.invalidResponse }
        return (result.id, result.feed_id)
    }

    public func addTag(_ name: String, to feedID: Int) async throws {
        _ = try await request("taggings.json", method: "POST", body: ["feed_id": feedID, "name": name])
    }

    public func renameTag(from oldName: String, to newName: String) async throws {
        _ = try await request("tags.json", method: "POST", body: ["old_name": oldName, "new_name": newName])
    }

    public func deleteTag(named name: String) async throws {
        _ = try await request("tags.json", method: "DELETE", body: ["name": name])
    }

    public func removeSubscription(_ subscriptionID: Int) async throws {
        _ = try await request("subscriptions/\(subscriptionID).json", method: "DELETE")
    }

    public func removeTagging(feedID: Int, name: String) async throws {
        let (data, _) = try await request("taggings.json")
        let matches = try JSONDecoder().decode([Tagging].self, from: data).filter { $0.feed_id == feedID && $0.name == name }
        for tagging in matches { _ = try await request("taggings/\(tagging.id).json", method: "DELETE") }
    }

    /// Mirrors Feedbin subscriptions and tags into Precis. Article downloads run through Refresh All.
    @MainActor public func sync(context: ModelContext) async throws -> Int {
        let (subscriptionData, _) = try await request("subscriptions.json")
        let subscriptions = try JSONDecoder().decode([Subscription].self, from: subscriptionData)
        let (taggingData, _) = try await request("taggings.json")
        let taggings = try JSONDecoder().decode([Tagging].self, from: taggingData)
        let tagsByID = Dictionary(grouping: taggings, by: \.feed_id).mapValues { Array(Set($0.map(\.name))).sorted() }
        let repository = FeedRepository()
        var added = 0
        for subscription in subscriptions {
            guard URL(string: subscription.feed_url) != nil else { continue }
            let matching = try repository.fetchAll(context: context).first { $0.feedbinSubscriptionID == subscription.id }
                ?? repository.existingFeed(forURL: subscription.feed_url, context: context)
            let feed: FeedRecord
            if let matching {
                feed = matching
            } else {
                feed = FeedRecord(title: subscription.title, url: subscription.feed_url, feedbinSubscriptionID: subscription.id)
                context.insert(feed)
                added += 1
            }
            feed.feedbinSubscriptionID = subscription.id
            feed.feedbinFeedID = subscription.feed_id
            feed.feedbinTagNames = tagsByID[subscription.feed_id] ?? []
            feed.title = subscription.title
        }
        try context.save()

        return added
    }
}

public struct OldReaderCredentials: Equatable, Sendable {
    public var username: String
    public var password: String
    public init(username: String, password: String) {
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        self.password = password
    }
}

/// The Old Reader login is an account password (OAuth-only accounts must first
/// set one in The Old Reader's account settings).
public enum OldReaderCredentialStore {
    private static let service = "com.precis.oldreader"
    private static let account = "credentials"

    public static func load() async -> OldReaderCredentials? {
        await Task.detached(priority: .userInitiated) {
            guard let data = read(),
                  let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
            return OldReaderCredentials(username: payload.username, password: payload.password)
        }.value
    }

    public static func save(_ credentials: OldReaderCredentials) async throws {
        let data = try JSONEncoder().encode(Payload(username: credentials.username, password: credentials.password))
        try await Task.detached(priority: .userInitiated) { try write(data) }.value
    }

    public static func delete() async {
        await Task.detached(priority: .userInitiated) {
            _ = SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary)
        }.value
    }

    private struct Payload: Codable, Sendable {
        let username: String
        let password: String
    }

    private static func read() -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary, &result)
        return status == errSecSuccess ? result as? Data : nil
    }

    private static func write(_ data: Data) throws {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus)) }
        var item = query
        item[kSecValueData] = data
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}

@MainActor public final class OldReaderService {
    private let credentials: OldReaderCredentials
    private let session: URLSession
    private let base = URL(string: "https://theoldreader.com")!

    public init(credentials: OldReaderCredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    private struct SubscriptionList: Decodable {
        let subscriptions: [Subscription]
    }
    private struct Subscription: Decodable {
        let id: String
        let title: String
        let url: String
        let categories: [Category]?
    }
    private struct Category: Decodable {
        let label: String?
    }
    private struct LoginResponse: Decodable {
        let Auth: String?
        let auth: String?
    }

    private func formBody(_ values: [(String, String)]) -> Data {
        var components = URLComponents()
        components.queryItems = values.map { URLQueryItem(name: $0.0, value: $0.1) }
        return Data((components.percentEncodedQuery ?? "").replacingOccurrences(of: "%20", with: "+").utf8)
    }

    private func authenticate() async throws -> String {
        var request = URLRequest(url: base.appending(path: "/accounts/ClientLogin"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formBody([
            ("client", "Precis"),
            ("accountType", "HOSTED_OR_GOOGLE"),
            ("service", "reader"),
            ("Email", credentials.username),
            ("Passwd", credentials.password),
            ("output", "json")
        ])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FeedbinError.oldReaderInvalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 { throw FeedbinError.invalidOldReaderCredentials }
            throw FeedbinError.oldReaderRequestFailed(http.statusCode)
        }
        if let result = try? JSONDecoder().decode(LoginResponse.self, from: data),
           let token = result.Auth ?? result.auth, !token.isEmpty { return token }
        let responseText = String(decoding: data, as: UTF8.self)
        if let line = responseText.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("Auth=") }) {
            let token = String(line.dropFirst("Auth=".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty { return token }
        }
        throw FeedbinError.invalidOldReaderCredentials
    }

    private func subscriptions(token: String) async throws -> [Subscription] {
        var components = URLComponents(url: base.appending(path: "/reader/api/0/subscription/list"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "output", value: "json")]
        var request = URLRequest(url: components.url!)
        request.setValue("GoogleLogin auth=\(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FeedbinError.oldReaderInvalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 { throw FeedbinError.invalidOldReaderCredentials }
            throw FeedbinError.oldReaderRequestFailed(http.statusCode)
        }
        return try JSONDecoder().decode(SubscriptionList.self, from: data).subscriptions
    }

    public func removeSubscription(_ subscriptionID: String) async throws {
        let token = try await authenticate()
        var request = URLRequest(url: base.appending(path: "/reader/api/0/subscription/edit"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("GoogleLogin auth=\(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = formBody([("ac", "unsubscribe"), ("s", subscriptionID)])
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FeedbinError.oldReaderInvalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 { throw FeedbinError.invalidOldReaderCredentials }
            throw FeedbinError.oldReaderRequestFailed(http.statusCode)
        }
    }

    /// Mirrors The Old Reader subscriptions and their folder labels into Precis.
    public func sync(context: ModelContext) async throws -> Int {
        let token = try await authenticate()
        let subscriptions = try await subscriptions(token: token)
        let repository = FeedRepository()
        var added = 0
        for subscription in subscriptions {
            guard URL(string: subscription.url)?.scheme?.hasPrefix("http") == true else { continue }
            let matching = try repository.fetchAll(context: context).first {
                $0.oldReaderSubscriptionID == subscription.id
            } ?? repository.existingFeed(forURL: subscription.url, context: context)
            let feed: FeedRecord
            if let matching {
                feed = matching
            } else {
                feed = FeedRecord(title: subscription.title, url: subscription.url)
                context.insert(feed)
                added += 1
            }
            feed.oldReaderSubscriptionID = subscription.id
            feed.oldReaderFolderNames = Array(Set(subscription.categories?.compactMap(\.label).filter { !$0.isEmpty } ?? [])).sorted()
            feed.title = subscription.title
        }
        try context.save()
        return added
    }
}

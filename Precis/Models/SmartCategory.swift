import Foundation

public enum SmartCategoryMatchMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case all
    case any
    public var id: String { rawValue }
}

public enum SmartCategoryField: String, Codable, CaseIterable, Identifiable, Sendable {
    case title, content, author, feed, category, publishedDate, readStatus, starred
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .title: "Title"
        case .content: "Content"
        case .author: "Author"
        case .feed: "Feed"
        case .category: "Category"
        case .publishedDate: "Date published"
        case .readStatus: "Read status"
        case .starred: "Starred"
        }
    }
    public var operators: [SmartCategoryOperator] {
        switch self {
        case .title, .content, .author, .feed, .category: [.contains, .doesNotContain, .equal, .notEqual, .beginsWith, .endsWith]
        case .publishedDate: [.inLastDays, .before, .after]
        case .readStatus: [.isRead, .isUnread]
        case .starred: [.equal, .notEqual]
        }
    }
}

public enum SmartCategoryOperator: String, Codable, CaseIterable, Identifiable, Sendable {
    case contains, doesNotContain
    case equal = "is"
    case notEqual = "isNot"
    case beginsWith, endsWith
    case inLastDays, before, after
    case isRead, isUnread
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .contains: "contains"
        case .doesNotContain: "does not contain"
        case .equal: "is"
        case .notEqual: "is not"
        case .beginsWith: "begins with"
        case .endsWith: "ends with"
        case .inLastDays: "is in the last N days"
        case .before: "is before"
        case .after: "is after"
        case .isRead: "is read"
        case .isUnread: "is unread"
        }
    }
}

public struct SmartCategoryRule: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var field: SmartCategoryField
    public var operation: SmartCategoryOperator
    public var value: String
    public init(id: UUID = UUID(), field: SmartCategoryField = .title, operation: SmartCategoryOperator = .contains, value: String = "") {
        self.id = id; self.field = field; self.operation = operation; self.value = value
    }
}

public indirect enum SmartCategoryCondition: Codable, Hashable, Sendable {
    case rule(SmartCategoryRule)
    case group(SmartCategoryRuleGroup)
}

public struct SmartCategoryRuleGroup: Codable, Hashable, Sendable {
    public var matchMode: SmartCategoryMatchMode
    public var children: [SmartCategoryCondition]
    public init(matchMode: SmartCategoryMatchMode = .all, children: [SmartCategoryCondition] = []) {
        self.matchMode = matchMode; self.children = children
    }
}

public struct SmartCategory: Identifiable, Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1
    public var id: UUID
    public var name: String
    public var colorHex: String?
    public var excludedFeedIDs: [UUID] = []
    public var matchMode: SmartCategoryMatchMode
    public var rootGroup: SmartCategoryRuleGroup
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var isDeleted: Bool
    public var schemaVersion: Int
    public init(id: UUID = UUID(), name: String, colorHex: String? = nil, excludedFeedIDs: [UUID] = [], matchMode: SmartCategoryMatchMode = .all, rootGroup: SmartCategoryRuleGroup = .init(), sortOrder: Int = 0, createdAt: Date = Date(), updatedAt: Date = Date(), isDeleted: Bool = false, schemaVersion: Int = currentSchemaVersion) {
        self.id = id; self.name = name; self.colorHex = colorHex; self.excludedFeedIDs = excludedFeedIDs; self.matchMode = matchMode; self.rootGroup = rootGroup; self.sortOrder = sortOrder; self.createdAt = createdAt; self.updatedAt = updatedAt; self.isDeleted = isDeleted; self.schemaVersion = schemaVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex)
        excludedFeedIDs = try container.decodeIfPresent([UUID].self, forKey: .excludedFeedIDs) ?? []
        matchMode = try container.decode(SmartCategoryMatchMode.self, forKey: .matchMode)
        rootGroup = try container.decode(SmartCategoryRuleGroup.self, forKey: .rootGroup)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isDeleted = try container.decode(Bool.self, forKey: .isDeleted)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    }
}

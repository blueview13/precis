import Foundation

public enum SmartFolderOperator: String, Codable {
    case all
    case any
}

public enum SmartFolderCriterionField: String, Codable {
    case title
    case content
    case feed
    case ageDays
    case readState
}

public struct SmartFolderCriterion: Codable {
    public var field: SmartFolderCriterionField
    public var value: String
    public var operatorSymbol: String

    public init(field: SmartFolderCriterionField, value: String, operatorSymbol: String = "==") {
        self.field = field
        self.value = value
        self.operatorSymbol = operatorSymbol
    }
}

public struct SmartFolder: Identifiable, Codable {
    public let id: UUID
    public var name: String
    public var operatorType: SmartFolderOperator
    public var criteria: [SmartFolderCriterion]

    public init(id: UUID = UUID(), name: String, operatorType: SmartFolderOperator = .all, criteria: [SmartFolderCriterion] = []) {
        self.id = id
        self.name = name
        self.operatorType = operatorType
        self.criteria = criteria
    }
}

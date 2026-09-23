import Foundation
import SwiftData

public protocol SummaryRepositoryProtocol {
    func fetchAll(context: ModelContext) throws -> [SummaryRecord]
    func save(_ summary: SummaryRecord, context: ModelContext) throws
    func fetch(for articleID: UUID, context: ModelContext) throws -> SummaryRecord?
}

public final class SummaryRepository: SummaryRepositoryProtocol {
    public init() {}

    public func fetchAll(context: ModelContext) throws -> [SummaryRecord] {
        let descriptor = FetchDescriptor<SummaryRecord>(sortBy: [SortDescriptor(\.generatedAt, order: .reverse)])
        return try context.fetch(descriptor)
    }

    public func save(_ summary: SummaryRecord, context: ModelContext) throws {
        context.insert(summary)
        try context.save()
    }

    public func fetch(for articleID: UUID, context: ModelContext) throws -> SummaryRecord? {
        let descriptor = FetchDescriptor<SummaryRecord>(
            predicate: #Predicate { $0.article?.id == articleID }
        )
        return try context.fetch(descriptor).first
    }
}

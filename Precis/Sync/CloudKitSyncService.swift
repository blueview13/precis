import Foundation

public protocol CloudKitSyncServiceProtocol {
    func syncFeeds() async throws
    func syncReadState() async throws
    func syncSummaries() async throws
}

public final class CloudKitSyncService: CloudKitSyncServiceProtocol {
    public init() {}

    public func syncFeeds() async throws {
        PrecisLogger.info("CloudKit feed sync requested")
    }

    public func syncReadState() async throws {
        PrecisLogger.info("CloudKit read-state sync requested")
    }

    public func syncSummaries() async throws {
        PrecisLogger.info("CloudKit summary sync requested")
    }
}

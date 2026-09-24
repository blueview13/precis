import Foundation

@MainActor
public protocol BackgroundRefreshServiceProtocol {
    func beginRefreshLoop(interval: RefreshInterval, onRefresh: @escaping @MainActor @Sendable () async -> Void)
    func stopRefreshLoop()
}

/// Coordinates the app-wide background refresh loop.
///
/// The refresh work itself is supplied by the caller — the view layer owns the
/// SwiftData context, so it performs the actual feed refreshes.
@MainActor
public final class BackgroundRefreshService: BackgroundRefreshServiceProtocol {
    private let scheduler: RefreshSchedulerProtocol

    public init(scheduler: RefreshSchedulerProtocol = RefreshScheduler()) {
        self.scheduler = scheduler
    }

    public func beginRefreshLoop(interval: RefreshInterval, onRefresh: @escaping @MainActor @Sendable () async -> Void) {
        scheduler.scheduleNextRefresh(interval: interval, onRefresh: onRefresh)
        PrecisLogger.info("Background refresh loop started (\(interval.displayName))")
    }

    public func stopRefreshLoop() {
        scheduler.pauseRefresh()
        PrecisLogger.info("Background refresh loop stopped")
    }
}

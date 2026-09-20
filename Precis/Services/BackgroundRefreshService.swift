import Foundation

public protocol BackgroundRefreshServiceProtocol {
    func beginRefreshLoop()
    func stopRefreshLoop()
}

public final class BackgroundRefreshService: BackgroundRefreshServiceProtocol {
    private let scheduler: RefreshSchedulerProtocol
    private let refreshPipeline: FeedRefreshPipelineProtocol

    public init(
        scheduler: RefreshSchedulerProtocol = RefreshScheduler(),
        refreshPipeline: FeedRefreshPipelineProtocol = FeedRefreshPipeline()
    ) {
        self.scheduler = scheduler
        self.refreshPipeline = refreshPipeline
    }

    public func beginRefreshLoop() {
        scheduler.scheduleNextRefresh(interval: .fifteenMinutes)
        PrecisLogger.info("Background refresh loop started")
    }

    public func stopRefreshLoop() {
        scheduler.pauseRefresh()
        PrecisLogger.info("Background refresh loop stopped")
    }
}

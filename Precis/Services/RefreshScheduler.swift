import Foundation

public protocol RefreshSchedulerProtocol {
    func scheduleNextRefresh(interval: RefreshInterval)
    func pauseRefresh()
    func resumeRefresh()
}

public final class RefreshScheduler: RefreshSchedulerProtocol {
    private var timer: Timer?

    public init() {}

    public func scheduleNextRefresh(interval: RefreshInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(interval.rawValue * 60), repeats: false) { _ in
            PrecisLogger.info("Scheduled refresh fired for interval \(interval.displayName)")
        }
    }

    public func pauseRefresh() {
        timer?.invalidate()
        timer = nil
    }

    public func resumeRefresh() {
        PrecisLogger.info("Refresh scheduler resumed")
    }
}

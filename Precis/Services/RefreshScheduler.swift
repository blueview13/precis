import Foundation

@MainActor
public protocol RefreshSchedulerProtocol {
    func scheduleNextRefresh(interval: RefreshInterval, onRefresh: @escaping @MainActor @Sendable () async -> Void)
    func pauseRefresh()
    func resumeRefresh()
}

/// Schedules repeating background refreshes.
///
/// The loop is driven by `Task.sleep` rather than `Timer`, so ticks keep firing
/// regardless of run-loop mode (window dragging, menu tracking), and tests can
/// exercise the loop quickly through the injected interval→seconds mapping.
@MainActor
public final class RefreshScheduler: RefreshSchedulerProtocol {
    private let secondsForInterval: @Sendable (RefreshInterval) -> TimeInterval
    private var refreshTask: Task<Void, Never>?
    private var lastInterval: RefreshInterval?
    private var lastHandler: (@MainActor @Sendable () async -> Void)?

    public init(
        secondsForInterval: @escaping @Sendable (RefreshInterval) -> TimeInterval = { TimeInterval($0.rawValue * 60) }
    ) {
        self.secondsForInterval = secondsForInterval
    }

    public func scheduleNextRefresh(interval: RefreshInterval, onRefresh: @escaping @MainActor @Sendable () async -> Void) {
        refreshTask?.cancel()
        lastInterval = interval
        lastHandler = onRefresh

        let seconds = secondsForInterval(interval)
        PrecisLogger.info("Scheduling refresh every \(interval.displayName)")

        refreshTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(seconds))
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                PrecisLogger.info("Scheduled refresh fired for interval \(interval.displayName)")
                await onRefresh()
            }
        }
    }

    public func pauseRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    public func resumeRefresh() {
        guard refreshTask == nil,
              let interval = lastInterval,
              let handler = lastHandler else { return }
        scheduleNextRefresh(interval: interval, onRefresh: handler)
    }
}

import Foundation
import Testing
@testable import Precis

@MainActor
struct RefreshSchedulerTests {

    @Test
    func refreshIntervalIncludesOneMinute() {
        #expect(RefreshInterval.oneMinute.rawValue == 1)
        #expect(RefreshInterval.oneMinute.displayName == "1 minute")
        #expect(RefreshInterval.allCases.count == 5)
    }

    @Test
    func schedulerFiresRepeatedlyAtConfiguredInterval() async {
        let counter = Counter()
        let scheduler = RefreshScheduler(secondsForInterval: { _ in 0.05 })

        scheduler.scheduleNextRefresh(interval: .oneMinute) {
            await counter.increment()
        }

        let firedTwice = await waitUntilCount(counter, atLeast: 2)
        scheduler.pauseRefresh()

        #expect(firedTwice)
    }

    @Test
    func pauseStopsFurtherRefreshes() async throws {
        let counter = Counter()
        let scheduler = RefreshScheduler(secondsForInterval: { _ in 0.05 })

        scheduler.scheduleNextRefresh(interval: .oneMinute) {
            await counter.increment()
        }

        let firedOnce = await waitUntilCount(counter, atLeast: 1)
        #expect(firedOnce)

        scheduler.pauseRefresh()
        let countAtPause = await counter.count

        try await Task.sleep(for: .milliseconds(250))
        let countAfterPause = await counter.count

        // At most one tick may still be landing from before the pause.
        #expect(countAfterPause <= countAtPause + 1)
    }

    @Test
    func backgroundServiceSchedulesConfiguredIntervalAndRunsWork() async {
        let mock = MockRefreshScheduler()
        let service = BackgroundRefreshService(scheduler: mock)
        let box = FlagBox()

        service.beginRefreshLoop(interval: .oneMinute) {
            box.value = true
        }

        #expect(mock.lastInterval == .oneMinute)
        #expect(!mock.paused)

        if let handler = mock.lastHandler {
            await handler()
        }
        #expect(box.value)

        service.stopRefreshLoop()
        #expect(mock.paused)
    }

    @Test
    func resumeRestartsTheLoop() async {
        let counter = Counter()
        let scheduler = RefreshScheduler(secondsForInterval: { _ in 0.05 })

        scheduler.scheduleNextRefresh(interval: .oneMinute) {
            await counter.increment()
        }
        scheduler.pauseRefresh()
        scheduler.resumeRefresh()

        let firedAgain = await waitUntilCount(counter, atLeast: 1)
        scheduler.pauseRefresh()

        #expect(firedAgain)
    }
}

// MARK: - Helpers

private actor Counter {
    var count = 0

    func increment() {
        count += 1
    }
}

@MainActor
private final class MockRefreshScheduler: RefreshSchedulerProtocol {
    private(set) var lastInterval: RefreshInterval?
    private(set) var lastHandler: (@MainActor @Sendable () async -> Void)?
    private(set) var paused = false

    func scheduleNextRefresh(interval: RefreshInterval, onRefresh: @escaping @MainActor @Sendable () async -> Void) {
        lastInterval = interval
        lastHandler = onRefresh
        paused = false
    }

    func pauseRefresh() {
        paused = true
    }

    func resumeRefresh() {}
}

@MainActor
private final class FlagBox {
    var value = false
}

private func waitUntilCount(_ counter: Counter, atLeast target: Int) async -> Bool {
    for _ in 0..<100 {
        if await counter.count >= target { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await counter.count >= target
}

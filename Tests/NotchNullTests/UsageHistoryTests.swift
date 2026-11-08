import XCTest
@testable import NotchNull

final class UsageHistoryTests: XCTestCase {
    func testDayPaceCountsDaysFromTheResetTimeNotMidnight() throws {
        let reset = start.addingTimeInterval(7 * 86_400 - 12 * 3600) // cycle began at noon the day before
        let morning = try XCTUnwrap(window(1, reset: reset).dayPace(at: start.addingTimeInterval(9 * 3600)))
        XCTAssertEqual(morning.day, 0) // 9 AM still belongs to the day that began at noon
        XCTAssertEqual(morning.dayStart, start.addingTimeInterval(-12 * 3600))
        XCTAssertEqual(morning.dayEnd, start.addingTimeInterval(12 * 3600))
        let afternoon = try XCTUnwrap(window(1, reset: reset).dayPace(at: start.addingTimeInterval(13 * 3600)))
        XCTAssertEqual(afternoon.day, 1)
        XCTAssertEqual(window(50, reset: reset).dayPace(at: reset.addingTimeInterval(-1))?.day, 6)
    }

    func testTodayMeasuresOnlyTodaysUsageAgainstAFixedAllowance() throws {
        let reset = start.addingTimeInterval(7 * 86_400)
        var history = UsageHistory()
        // Day 1 starts at zero by definition, even when first seen hours later.
        XCTAssertTrue(history.record(window(4, reset: reset), at: start.addingTimeInterval(5 * 3600), now: start.addingTimeInterval(5 * 3600)))
        XCTAssertTrue(history.record(window(9, reset: reset), at: start.addingTimeInterval(86_400 - 300), now: start.addingTimeInterval(86_400 - 300)))
        // First reading after the boundary: yesterday ended at 9%, today's baseline is known.
        let morning = start.addingTimeInterval(86_400 + 300)
        XCTAssertTrue(history.record(window(9.5, reset: reset), at: morning, now: morning))
        let later = start.addingTimeInterval(86_400 + 6 * 3600)
        XCTAssertTrue(history.record(window(12, reset: reset), at: later, now: later))
        let days = history.days(for: window(12, reset: reset))
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].used, 9, accuracy: 0.001)
        XCTAssertEqual(days[0].allowance, 100.0 / 7, accuracy: 0.001)
        XCTAssertEqual(days[0].complete, true)
        XCTAssertTrue(days[1].exact)
        XCTAssertEqual(days[1].used, 3, accuracy: 0.001)
        // Unused quota from day 1 raises day 2's allowance, which stays fixed during the day.
        XCTAssertEqual(days[1].allowance, 91.0 / 6, accuracy: 0.001)
        XCTAssertFalse(days[1].over)
    }

    func testUnobservedBoundaryStartsTodayAtTheFirstReadingInsteadOfGuessing() throws {
        let reset = start.addingTimeInterval(7 * 86_400)
        var history = UsageHistory()
        XCTAssertTrue(history.record(window(9, reset: reset), at: start.addingTimeInterval(20 * 3600), now: start.addingTimeInterval(20 * 3600)))
        // The Mac slept across the boundary; the counter moved meanwhile.
        let wake = start.addingTimeInterval(86_400 + 3 * 3600)
        XCTAssertTrue(history.record(window(15, reset: reset), at: wake, now: wake))
        let days = history.days(for: window(15, reset: reset))
        XCTAssertEqual(days[0].complete, false)
        XCTAssertFalse(days[1].exact)
        XCTAssertEqual(days[1].since, wake)
        XCTAssertEqual(days[1].used, 0)
        XCTAssertEqual(days[1].allowance, 85.0 / 6, accuracy: 0.001)
    }

    func testOverspendingIsFlaggedAndNewCycleClearsDays() throws {
        let reset = start.addingTimeInterval(7 * 86_400)
        var history = UsageHistory()
        XCTAssertTrue(history.record(window(20, reset: reset), at: start.addingTimeInterval(3600), now: start.addingTimeInterval(3600)))
        XCTAssertTrue(try XCTUnwrap(history.days(for: window(20, reset: reset)).last).over)
        let next = reset.addingTimeInterval(3600)
        XCTAssertTrue(history.record(window(1, reset: reset.addingTimeInterval(7 * 86_400)), at: next, now: next))
        XCTAssertEqual(history.days(for: window(1, reset: reset.addingTimeInterval(7 * 86_400))).map(\.day), [0])
        XCTAssertTrue(history.days(for: window(20, reset: reset)).isEmpty)
    }

    func testDayPaceNeedsAMultiDayWindowBeforeItsReset() {
        let reset = start.addingTimeInterval(5 * 3600)
        XCTAssertNil(UsageWindow(id: "s", label: "Session", percent: 10, resetsAt: reset, duration: 5 * 3600).dayPace(at: start))
        XCTAssertNil(UsageWindow(id: "w", label: "Week", percent: 10, resetsAt: nil, duration: 7 * 86_400).dayPace(at: start))
        XCTAssertNil(window(10, reset: start).dayPace(at: start))
        XCTAssertNil(window(10, reset: start.addingTimeInterval(9 * 86_400)).dayPace(at: start))
    }

    @MainActor
    func testDisabledCleanupAndMissingPlansSurviveRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        let reset = start.addingTimeInterval(7 * 86_400)
        let store = UsageHistoryStore(url: url, now: start)
        for provider in ["claude", "codex", "zai", "kimi"] {
            store.record(provider: provider, plan: nil, windows: [window(1, reset: reset)], updatedAt: start, state: .ready, now: start)
        }
        XCTAssertFalse(store.isCleanupScheduled)
        store.setActive(true, now: start)
        XCTAssertTrue(store.isCleanupScheduled)
        store.interrupt(provider: "claude")
        store.interruptMissingPlans(present: ["kimi"])
        store.setActive(false, now: start)
        XCTAssertFalse(store.isCleanupScheduled)
        store.waitForPendingWrites()
        let restored = UsageHistoryStore(url: url, now: start)
        XCTAssertFalse(restored.isCleanupScheduled)
        let recovered = start.addingTimeInterval(1800)
        for provider in ["claude", "codex", "zai", "kimi"] {
            restored.record(provider: provider, plan: nil, windows: [window(1, reset: reset)], updatedAt: recovered, state: .ready, now: recovered)
        }
        restored.waitForPendingWrites()
        let saved = try JSONDecoder().decode([String: UsageHistory].self, from: Data(contentsOf: url))
        for provider in ["claude", "codex", "zai", "kimi"] {
            let key = UsageHistoryStore.key(provider: provider, plan: nil, window: window(1, reset: reset))
            XCTAssertEqual(saved[key]?.intervals.count, ["claude", "zai"].contains(provider) ? 0 : 1)
        }
        restored.setActive(true, now: start.addingTimeInterval(29 * 86_400))
        XCTAssertFalse(restored.isCleanupScheduled)
        restored.waitForPendingWrites()
        XCTAssertTrue(try JSONDecoder().decode([String: UsageHistory].self, from: Data(contentsOf: url)).isEmpty)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private let start = Date(timeIntervalSince1970: 1_800_057_600) // midnight UTC
    private func window(_ used: Double, reset: Date) -> UsageWindow {
        UsageWindow(id: "week", label: "Week", percent: used, resetsAt: reset, duration: 7 * 86_400)
    }

    func testFirstDayBudgetDoesNotExtrapolateBurst() throws {
        let now = start.addingTimeInterval(10 * 3600)
        let week = window(7, reset: start.addingTimeInterval(7 * 86_400))
        XCTAssertEqual(try XCTUnwrap(week.dailyBudget(at: now)), 93 / (7 - 10.0 / 24), accuracy: 0.001)
        var history = UsageHistory()
        XCTAssertTrue(history.record(week, at: now, now: now))
        XCTAssertNil(history.forecast(week, at: now, calendar: calendar))
    }

    func testBudgetAfterFullDayAndNearReset() throws {
        let reset = start.addingTimeInterval(7 * 86_400)
        XCTAssertEqual(try XCTUnwrap(window(7, reset: reset).dailyBudget(at: start.addingTimeInterval(86_400))), 15.5)
        XCTAssertEqual(window(93, reset: reset).dailyBudget(at: reset.addingTimeInterval(-3600)), 7)
        XCTAssertNil(window(7, reset: reset).dailyBudget(at: reset))
    }

    func testDuplicateOldStaleFutureAndOfflineObservationsAreNotLearned() {
        var history = UsageHistory()
        let reset = start.addingTimeInterval(7 * 86_400)
        let week = window(7, reset: reset)
        XCTAssertTrue(history.record(week, at: start, now: start))
        XCTAssertFalse(history.record(week, at: start, now: start))
        XCTAssertFalse(history.record(week, at: start.addingTimeInterval(-1), now: start))
        XCTAssertFalse(history.record(week, at: start.addingTimeInterval(1), now: start))
        XCTAssertFalse(history.record(week, at: start.addingTimeInterval(60), now: start.addingTimeInterval(1800)))
        let later = start.addingTimeInterval(7200)
        XCTAssertTrue(history.record(window(9, reset: reset), at: later, now: later))
        XCTAssertTrue(history.intervals.isEmpty)
    }

    func testResetDoesNotBecomeConsumptionAndCorrectionClearsLearning() {
        var history = UsageHistory()
        let reset = start.addingTimeInterval(3600)
        XCTAssertTrue(history.record(window(90, reset: reset), at: start, now: start))
        let next = reset.addingTimeInterval(60)
        let nextReset = reset.addingTimeInterval(7 * 86_400)
        XCTAssertTrue(history.record(window(2, reset: nextReset), at: next, now: next))
        XCTAssertTrue(history.intervals.isEmpty)
        XCTAssertTrue(history.record(window(3, reset: nextReset), at: next.addingTimeInterval(600), now: next.addingTimeInterval(600)))
        XCTAssertEqual(history.intervals.count, 1)
        XCTAssertTrue(history.record(window(1, reset: nextReset), at: next.addingTimeInterval(1200), now: next.addingTimeInterval(1200)))
        XCTAssertTrue(history.intervals.isEmpty)
    }

    func testExhaustedIntervalsDoNotCountAsObservedInactivity() {
        var history = UsageHistory()
        let reset = start.addingTimeInterval(7 * 86_400)
        for (index, percent) in [99.0, 100, 100, 100].enumerated() {
            let date = start.addingTimeInterval(Double(index) * 600)
            XCTAssertTrue(history.record(window(percent, reset: reset), at: date, now: date))
        }
        XCTAssertTrue(history.intervals.isEmpty)
        let next = reset.addingTimeInterval(60)
        XCTAssertTrue(history.record(window(1, reset: reset.addingTimeInterval(7 * 86_400)), at: next, now: next))
        XCTAssertTrue(history.intervals.isEmpty)
    }

    func testInterruptedRecoveryStillInvalidatesChangedScale() {
        let reset = start.addingTimeInterval(7 * 86_400)
        for changedDuration in [false, true] {
            var history = UsageHistory()
            XCTAssertTrue(history.record(window(10, reset: reset), at: start, now: start))
            let second = start.addingTimeInterval(600)
            XCTAssertTrue(history.record(window(11, reset: reset), at: second, now: second))
            history.interrupted = true
            let recovery = start.addingTimeInterval(1200)
            let changed = UsageWindow(id: "week", label: "Week", percent: changedDuration ? 12 : 9,
                                      resetsAt: reset, duration: (changedDuration ? 8 : 7) * 86_400)
            XCTAssertTrue(history.record(changed, at: recovery, now: recovery))
            XCTAssertTrue(history.intervals.isEmpty)
        }
    }

    @MainActor
    func testStartupAndPeriodicCleanupPruneInactiveHistoriesOnDisk() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("history.json")
        let now = Date()
        let week = window(1, reset: now.addingTimeInterval(86_400))
        let key = UsageHistoryStore.key(provider: "claude", plan: nil, window: week)
        var history = UsageHistory()
        history.last = .init(date: now.addingTimeInterval(-86_400), percent: 1, reset: now.addingTimeInterval(86_400), duration: 7 * 86_400)
        history.intervals = [
            .init(start: now.addingTimeInterval(-29 * 86_400), end: now.addingTimeInterval(-29 * 86_400 + 600), used: 1),
            .init(start: now.addingTimeInterval(-27 * 86_400), end: now.addingTimeInterval(-27 * 86_400 + 600), used: 2)
        ]
        try JSONEncoder().encode([key: history]).write(to: url)
        let store = UsageHistoryStore(url: url, now: now, scheduleCleanup: false)
        store.waitForPendingWrites()
        let saved = try JSONDecoder().decode([String: UsageHistory].self, from: Data(contentsOf: url))
        XCTAssertEqual(saved[key]?.intervals.count, 1)
        store.cleanup(at: now.addingTimeInterval(2 * 86_400))
        store.waitForPendingWrites()
        let later = try JSONDecoder().decode([String: UsageHistory].self, from: Data(contentsOf: url))
        XCTAssertTrue(try XCTUnwrap(later[key]).intervals.isEmpty)
    }

    private func learnedHistory() -> (UsageHistory, Date, Date) {
        var history = UsageHistory()
        let reset = start.addingTimeInterval(7 * 86_400)
        var used = 0.0
        _ = history.record(window(used, reset: reset), at: start, now: start)
        for hour in 0..<72 {
            let date = start.addingTimeInterval(Double(hour) * 3600)
            let localHour = calendar.component(.hour, from: date)
            // Night quiet, work from 09:00 to 02:00, 17 points per day.
            used += localHour >= 9 || localHour < 2 ? 1 : 0
            let end = date.addingTimeInterval(3600)
            _ = history.record(window(used, reset: reset), at: end, now: end)
        }
        return (history, start.addingTimeInterval(72 * 3600), reset)
    }

    func testLearnsWorkingHoursInsteadOfPredictingOvernightBurn() throws {
        let (history, now, reset) = learnedHistory()
        let rates = try XCTUnwrap(history.hourlyRates(calendar: calendar))
        XCTAssertEqual(rates[6], 0)
        XCTAssertEqual(rates[10], 1, accuracy: 0.001)
        let forecast = try XCTUnwrap(history.forecast(window(51, reset: reset), at: now, calendar: calendar))
        XCTAssertEqual(forecast.dailyUse, 17, accuracy: 0.001)
        // 49 points left: two 17-point days, then 15 working hours, ending at 22:00.
        let hit = try XCTUnwrap(forecast.exhaustion)
        XCTAssertEqual(hit.timeIntervalSince(now), (48 + 22) * 3600, accuracy: 1)
        XCTAssertNil(history.forecast(window(51, reset: reset), at: now.addingTimeInterval(1201), calendar: calendar))
    }

    func testMissingHoursAreUnknownAndPersistencePreservesModel() throws {
        let (history, now, reset) = learnedHistory()
        var sparse = history
        sparse.intervals.removeAll { calendar.component(.hour, from: $0.start) == 6 }
        XCTAssertNil(sparse.forecast(window(51, reset: reset), at: now, calendar: calendar))
        let decoded = try JSONDecoder().decode(UsageHistory.self, from: JSONEncoder().encode(history))
        XCTAssertEqual(decoded.forecast(window(51, reset: reset), at: now, calendar: calendar)?.dailyUse, 17)
    }

    func testNoExhaustionWhenHabitsFitRemainingQuota() throws {
        var (history, now, reset) = learnedHistory()
        history.last?.percent = 7
        let forecast = try XCTUnwrap(history.forecast(window(7, reset: reset), at: now, calendar: calendar))
        XCTAssertNil(forecast.exhaustion)
        XCTAssertNil(history.forecast(window(100, reset: reset), at: now, calendar: calendar))
    }

    func testFrequentObservationsCoalesceWithoutLosingConsumption() throws {
        var history = UsageHistory()
        let reset = start.addingTimeInterval(7 * 86_400)
        for second in 0...1800 {
            let date = start.addingTimeInterval(Double(second))
            _ = history.record(window(Double(second) / 1800, reset: reset), at: date, now: date)
        }
        XCTAssertLessThanOrEqual(history.intervals.count, 2)
        XCTAssertEqual(history.intervals.reduce(0) { $0 + $1.used }, 1, accuracy: 0.0001)
    }

    func testOldHistoryExpiresInsteadOfInfluencingNewHabits() {
        var (history, _, _) = learnedHistory()
        let now = start.addingTimeInterval(40 * 86_400)
        let week = window(7, reset: now.addingTimeInterval(6 * 86_400))
        XCTAssertTrue(history.record(week, at: now, now: now))
        XCTAssertTrue(history.intervals.isEmpty)
        XCTAssertNil(history.forecast(week, at: now, calendar: calendar))
    }

    @MainActor
    func testUnavailableBreaksContinuityAcrossRestartWithoutDiscardingHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        let reset = start.addingTimeInterval(7 * 86_400)
        let key = UsageHistoryStore.key(provider: "claude", plan: "Max", window: window(1, reset: reset))
        let store = UsageHistoryStore(url: url, now: start, scheduleCleanup: false)
        for (minutes, percent) in [(0, 1.0), (10, 2.0)] {
            let date = start.addingTimeInterval(Double(minutes) * 60)
            store.record(provider: "claude", plan: "Max", windows: [window(percent, reset: reset)], updatedAt: date, state: .ready, now: date)
        }
        store.record(provider: "claude", plan: nil, windows: [], updatedAt: nil, state: .unavailable("offline"), now: start.addingTimeInterval(1200))
        store.waitForPendingWrites()
        let restored = UsageHistoryStore(url: url, now: start.addingTimeInterval(1800), scheduleCleanup: false)
        let recovered = start.addingTimeInterval(2400)
        restored.record(provider: "claude", plan: "Max", windows: [window(3, reset: reset)], updatedAt: recovered, state: .ready, now: recovered)
        restored.waitForPendingWrites()
        let saved = try JSONDecoder().decode([String: UsageHistory].self, from: Data(contentsOf: url))
        XCTAssertEqual(saved[key]?.intervals.count, 1)
        XCTAssertEqual(saved[key]?.intervals.first?.used, 1)
        let next = recovered.addingTimeInterval(600)
        restored.record(provider: "claude", plan: "Max", windows: [window(4, reset: reset)], updatedAt: next, state: .ready, now: next)
        restored.waitForPendingWrites()
        let later = try JSONDecoder().decode([String: UsageHistory].self, from: Data(contentsOf: url))
        XCTAssertEqual(later[key]?.intervals.count, 2)
    }

    @MainActor
    func testStoreSeparatesProvidersAndPlansAndRejectsUnavailableReadings() {
        let store = UsageHistoryStore(url: nil)
        let (_, now, reset) = learnedHistory()
        let week = window(51, reset: reset)
        store.record(provider: "claude", plan: "Max", windows: [week], updatedAt: now, state: .unavailable("stale"), now: now)
        XCTAssertNil(store.forecast(provider: "claude", plan: "Max", window: week, at: now))
        XCTAssertNotEqual(UsageHistoryStore.key(provider: "claude", plan: "Max", window: week),
                          UsageHistoryStore.key(provider: "codex", plan: "Max", window: week))
        XCTAssertNotEqual(UsageHistoryStore.key(provider: "claude", plan: "Max", window: week),
                          UsageHistoryStore.key(provider: "claude", plan: "Pro", window: week))
    }
}

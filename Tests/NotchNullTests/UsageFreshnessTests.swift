import XCTest
@testable import NotchNull

@MainActor
final class UsageFreshnessTests: XCTestCase {
    func testUsageChecksAreTenMinutesApart() {
        XCTAssertEqual(Constants.Agents.claudeUsageInterval, 600)
        XCTAssertEqual(Constants.Agents.codexUsageInterval, 600)
        XCTAssertEqual(Constants.Agents.planUsageInterval, 600)
    }

    func testCodexReadingStaysCurrentBetweenScheduledChecks() {
        let monitor = CodexMonitor(store: AgentSessionStore())
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let payload: [String: Any] = ["primary": ["used_percent": 15, "window_minutes": 10080, "resets_at": 2_000_000_000]]
        monitor.applyLimits(payload, at: now.addingTimeInterval(-599), now: now)
        XCTAssertEqual(monitor.usage.state, .ready)
    }

    func testCodexLiveResponseUsesAccountWindows() throws {
        let payload = try XCTUnwrap(CodexLimitsClient.normalize([
            "rateLimits": ["planType": "pro", "primary": ["usedPercent": 25, "windowDurationMins": 10080, "resetsAt": 2_000_000_000]]
        ]))
        let monitor = CodexMonitor(store: AgentSessionStore())
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        monitor.applyLimits(payload, at: now, now: now)
        XCTAssertEqual(monitor.usage.windows.first?.percent, 25)
        XCTAssertEqual(monitor.usage.windows.first?.label, "Week")
        XCTAssertEqual(monitor.usage.plan, "Pro")
        XCTAssertEqual(monitor.usage.state, .ready)
    }

    func testOldCodexSnapshotIsNotReadyAndExpiredWindowDoesNotBecomeUnused() {
        let monitor = CodexMonitor(store: AgentSessionStore())
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let payload: [String: Any] = ["primary": ["used_percent": 15, "window_minutes": 10080, "resets_at": 2_000_000_000]]
        monitor.applyLimits(payload, at: now.addingTimeInterval(-7 * 3600), now: now)
        XCTAssertEqual(monitor.usage.state, .unavailable("Last known limits · awaiting refresh"))
        XCTAssertEqual(monitor.usage.windows.first?.percent, 15)
        monitor.applyLimits(payload, at: now, now: Date(timeIntervalSince1970: 2_000_000_001))
        XCTAssertTrue(monitor.usage.windows.isEmpty)
        XCTAssertNotEqual(monitor.usage.state, .ready)
    }

    func testEmptyCodexResponseDoesNotConfirmFreshLimits() {
        XCTAssertNil(CodexLimitsClient.normalize(["rateLimits": ["planType": "pro"]]))
    }

    func testGoErrorsDoNotInventSubscription() {
        let service = PlanUsageService()
        let credential = PlanCredential(key: "fixture", source: "OpenCode")
        service.apply([(OpenCodeGoPlan(), credential, .failure(.unavailable("Offline")))])
        XCTAssertTrue(service.usages.isEmpty)
        service.apply([(OpenCodeGoPlan(), credential, .failure(.signedOut("Rejected")))])
        XCTAssertTrue(service.usages.isEmpty)
        let window = UsageWindow(id: "week", label: "Week", percent: 10, resetsAt: nil, duration: nil)
        service.apply([(OpenCodeGoPlan(), credential, .success(PlanSnapshot(windows: [window])))])
        XCTAssertEqual(service.usages.count, 1)
        service.apply([(OpenCodeGoPlan(), credential, .failure(.unavailable("Offline")))])
        XCTAssertEqual(service.usages.first?.windows, [window])
        service.apply([(OpenCodeGoPlan(), credential, .failure(.noSubscription))])
        XCTAssertTrue(service.usages.isEmpty)
    }
}

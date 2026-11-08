import XCTest
@testable import NotchNull

final class ClaudeSharedUsageTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func fixture(age: Double = 60, reset: Double = 3600, percent: Double = 8, provider: String = "claude") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["version": 1, "source": "mendcode", "quota": [
            ["provider": provider, "window": "5h", "usedPercent": percent,
             "observedAt": (now.timeIntervalSince1970 - age) * 1000,
             "resetsAt": (now.timeIntervalSince1970 + reset) * 1000]
        ]])
    }

    func testFreshExportPreservesNumbersAndObservationTime() throws {
        let result = ClaudeSharedUsage.parse(try fixture(), now: now)
        XCTAssertEqual(result.state, .ready)
        XCTAssertEqual(result.windows.first?.percent, 8)
        XCTAssertEqual(result.windows.first?.label, "5 hours")
        XCTAssertEqual(result.updatedAt, now.addingTimeInterval(-60))
        XCTAssertEqual(result.windows.first?.resetsAt, now.addingTimeInterval(3600))
        XCTAssertNil(result.plan)
    }

    func testPlanNamesPreserveDistinctSubscriptions() throws {
        for (raw, expected) in [(" ultra ", "Ultra"), ("max", "Max"), ("pro", "Pro"), ("team", "Team")] {
            XCTAssertEqual(ClaudeUsageService.planName(raw), expected)
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
            object["plan"] = raw
            let usage = ClaudeSharedUsage.parse(try JSONSerialization.data(withJSONObject: object), now: now)
            XCTAssertEqual(usage.plan, expected)
            XCTAssertEqual(usage.windows.first?.percent, 8)
        }
    }

    func testStaleReadingDoesNotBecomeFreshWhenFileIsRewritten() throws {
        let result = ClaudeSharedUsage.parse(try fixture(age: 1201), now: now)
        XCTAssertNotEqual(result.state, .ready)
        XCTAssertEqual(result.windows.first?.percent, 8)
    }

    func testInvalidExpiredOtherProviderAndFutureReadingsAreUnknown() throws {
        for data in [Data("broken".utf8), try fixture(reset: -1), try fixture(percent: 101),
                     try fixture(provider: "codex"), try fixture(age: -120)] {
            let result = ClaudeSharedUsage.parse(data, now: now)
            XCTAssertNotEqual(result.state, .ready)
            XCTAssertTrue(result.windows.isEmpty)
        }
    }

    func testOlderExportDoesNotOverwriteNewerObservation() throws {
        let shared = ClaudeSharedUsage.parse(try fixture(age: 60), now: now)
        let newer = ProviderUsage(provider: .claude, updatedAt: now.addingTimeInterval(-10), state: .ready)
        XCTAssertFalse(ClaudeSharedUsage.supersedes(shared, current: newer))
        XCTAssertTrue(ClaudeSharedUsage.supersedes(shared, current: .placeholder(.claude)))
        XCTAssertFalse(ClaudeSharedUsage.supersedes(ClaudeSharedUsage.unavailable(), current: newer))
    }

    func testSameObservationTransitionsToStale() throws {
        let data = try fixture()
        let fresh = ClaudeSharedUsage.parse(data, now: now)
        let stale = ClaudeSharedUsage.parse(data, now: now.addingTimeInterval(1201))
        XCTAssertNotEqual(stale.state, .ready)
        XCTAssertTrue(ClaudeSharedUsage.supersedes(stale, current: fresh))
    }

    func testMissingFileDiffersFromConfiguredButInvalidBridge() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("usage.json")
        XCTAssertNil(ClaudeSharedUsage.read(at: url, now: now))
        try Data("broken".utf8).write(to: url)
        XCTAssertEqual(ClaudeSharedUsage.read(at: url, now: now)?.state, ClaudeSharedUsage.unavailable().state)
    }
}

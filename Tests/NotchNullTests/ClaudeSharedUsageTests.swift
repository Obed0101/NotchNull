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

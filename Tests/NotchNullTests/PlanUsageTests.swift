import XCTest
@testable import NotchNull

final class PlanUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: Z.ai

    func testZaiOrdersPromptWindowsByLengthAndKeepsMCPLast() throws {
        let resetMs = Int((now.timeIntervalSince1970 + 3600) * 1000)
        let json = """
        {"code":200,"success":true,"msg":"ok","data":{"level":"pro","limits":[
          {"type":"TIME_LIMIT","unit":5,"number":1,"percentage":12,"usage":1000,"currentValue":120,"remaining":880},
          {"type":"TOKENS_LIMIT","unit":6,"number":1,"percentage":40},
          {"type":"TOKENS_LIMIT","unit":3,"number":5,"percentage":25,"nextResetTime":\(resetMs)}
        ]}}
        """
        let snapshot = try ZaiPlan.parse(Data(json.utf8), now: now)
        XCTAssertEqual(snapshot.windows.map(\.label), ["5 hours", "Week", "MCP"])
        XCTAssertEqual(snapshot.windows[0].percent, 25)
        XCTAssertEqual(snapshot.windows[0].duration, 5 * 3600)
        XCTAssertEqual(snapshot.windows[0].resetsAt?.timeIntervalSince1970 ?? 0, now.timeIntervalSince1970 + 3600, accuracy: 1)
        XCTAssertEqual(snapshot.windows[2].percent, 12)
        XCTAssertEqual(snapshot.plan, "Pro")
    }

    func testZaiDropsAFiveHourResetThatIsImplausiblyFarAway() throws {
        let farMs = Int((now.timeIntervalSince1970 + 10 * 3600) * 1000)
        let json = #"{"code":200,"success":true,"data":{"limits":[{"type":"TOKENS_LIMIT","unit":3,"number":5,"percentage":5,"nextResetTime":\#(farMs)}]}}"#
        XCTAssertNil(try ZaiPlan.parse(Data(json.utf8), now: now).windows.first?.resetsAt)
    }

    func testZaiReportsRejectedKeyFromTheBodyCodeEvenWithHTTP200() {
        let json = #"{"code":401,"msg":"token expired or incorrect","success":false}"#
        XCTAssertThrowsError(try ZaiPlan.parse(Data(json.utf8))) { error in
            XCTAssertEqual(error as? PlanError, .signedOut("Key rejected by Z.ai"))
        }
    }

    func testZaiWithoutLimitsIsNoSubscription() {
        let json = #"{"code":200,"success":true,"data":{"limits":[]}}"#
        XCTAssertThrowsError(try ZaiPlan.parse(Data(json.utf8))) { XCTAssertEqual($0 as? PlanError, .noSubscription) }
    }

    // MARK: Kimi

    func testKimiReadsRatioPools() throws {
        let json = """
        {"usages":{"limit_5h":{"used_ratio":0.3,"reset_time":"2026-09-30T18:00:00Z"},
                   "limit_7d":{"used_ratio":0.55,"reset_time":"2026-10-04T00:00:00Z"}},
         "user":{"membership":{"level":"LEVEL_INTERMEDIATE"}}}
        """
        let snapshot = try KimiPlan.parse(Data(json.utf8))
        XCTAssertEqual(snapshot.windows.map(\.label), ["5 hours", "Week"])
        XCTAssertEqual(snapshot.windows[0].percent, 30, accuracy: 0.001)
        XCTAssertNotNil(snapshot.windows[1].resetsAt)
        XCTAssertEqual(snapshot.plan, "Allegretto")
    }

    func testKimiFallsBackToLegacyCountsWithStringNumbers() throws {
        let json = """
        {"usage":{"limit":"2048","used":"512","resetTime":"2026-10-04T00:00:00Z"},
         "limits":[{"window":{"duration":300,"timeUnit":"TIME_UNIT_MINUTE"},"detail":{"limit":"200","remaining":"150"}}]}
        """
        let snapshot = try KimiPlan.parse(Data(json.utf8))
        XCTAssertEqual(snapshot.windows.map(\.label), ["5 hours", "Week"])
        XCTAssertEqual(snapshot.windows[0].percent, 25)
        XCTAssertEqual(snapshot.windows[1].percent, 25)
    }

    // MARK: MiniMax

    func testMiniMaxTreatsUsageCountAsRemainingPrompts() throws {
        let start = Int(now.timeIntervalSince1970 * 1000)
        let end = start + 5 * 3600 * 1000
        let json = """
        {"model_remains":[{"model_name":"MiniMax-M2","current_interval_total_count":1500,"current_interval_usage_count":1200,
          "start_time":\(start),"end_time":\(end),"remains_time":18000000}],
         "base_resp":{"status_code":0,"status_msg":"success"}}
        """
        let snapshot = try MiniMaxPlan.parse(Data(json.utf8), now: now)
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].label, "5 hours")
        XCTAssertEqual(snapshot.windows[0].percent, 20)
    }

    func testMiniMaxStatusCodeInBodyMeansSignedOut() {
        let json = #"{"base_resp":{"status_code":1004,"status_msg":"cookie is missing, log in again"}}"#
        XCTAssertThrowsError(try MiniMaxPlan.parse(Data(json.utf8))) { XCTAssertEqual($0 as? PlanError, .signedOut("Key rejected by MiniMax")) }
    }

    // MARK: OpenCode Go

    func testOpenCodeGoReadsPercentUnitsAndResetSeconds() throws {
        let json = #"{"usage":{"rolling":{"percent":3,"resetInSec":18100},"weekly":{"percent":41.5,"resetInSec":86400}}}"#
        let snapshot = try OpenCodeGoPlan.parse(Data(json.utf8), now: now)
        XCTAssertEqual(snapshot.windows.map(\.label), ["5 hours", "Week"])
        XCTAssertEqual(snapshot.windows[0].percent, 3)
        XCTAssertEqual(snapshot.windows[1].percent, 41.5)
        XCTAssertEqual(snapshot.windows[0].resetsAt, now.addingTimeInterval(18100))
    }

    func testOpenCodeGoReadsTheMonthlyWindowAndAbsoluteResetDates() throws {
        // The live response describes each window with an absolute `resetsAt` ISO date and a status.
        let json = """
        {"usage":{"rolling":{"status":"ok","percent":5,"resetsAt":"2026-10-16T01:00:48.000Z"},
                  "weekly":{"status":"ok","percent":22,"resetsAt":"2026-10-19T00:00:00.000Z"},
                  "monthly":{"status":"ok","percent":11,"resetsAt":"2026-11-15T14:52:07.000Z"}}}
        """
        let snapshot = try OpenCodeGoPlan.parse(Data(json.utf8), now: now)
        XCTAssertEqual(snapshot.windows.map(\.label), ["5 hours", "Week", "Month"])
        XCTAssertEqual(snapshot.windows.map(\.percent), [5, 22, 11])
        XCTAssertEqual(snapshot.windows[2].duration, 30 * 86_400)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(snapshot.windows[0].resetsAt, iso.date(from: "2026-10-16T01:00:48.000Z"))
        XCTAssertEqual(snapshot.windows[2].resetsAt, iso.date(from: "2026-11-15T14:52:07.000Z"))
    }

    func testOpenCodeGoEmptyOrMalformedPayloadsAreSafe() {
        XCTAssertThrowsError(try OpenCodeGoPlan.parse(Data(#"{"usage":{}}"#.utf8))) { XCTAssertEqual($0 as? PlanError, .noSubscription) }
        XCTAssertThrowsError(try OpenCodeGoPlan.parse(Data("not json".utf8))) { XCTAssertEqual($0 as? PlanError, .unavailable("Unreadable OpenCode response")) }
    }

    // MARK: Copilot

    func testCopilotSkipsUnlimitedQuotasAndConvertsRemainingToUsed() throws {
        let json = """
        {"copilot_plan":"individual_pro","quota_reset_date":"2026-11-01",
         "quota_snapshots":{"chat":{"unlimited":true,"percent_remaining":100},
                            "premium_interactions":{"entitlement":300,"remaining":210,"percent_remaining":70,"unlimited":false}}}
        """
        let snapshot = try CopilotPlan.parse(Data(json.utf8))
        XCTAssertEqual(snapshot.windows.map(\.label), ["Premium"])
        XCTAssertEqual(snapshot.windows[0].percent, 30)
        XCTAssertNotNil(snapshot.windows[0].duration)
        XCTAssertEqual(snapshot.plan, "Individual Pro")
    }

    // MARK: Credentials

    func testFindsKeysInOpenCodeAuthAndClaudeCodeSettings() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let openCode = home.appendingPathComponent(".local/share/opencode")
        let claude = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: openCode, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try Data(#"{"kimi-for-coding":{"type":"api","key":"kimi-key"},"opencode-go":{"type":"api","key":"go-key"}}"#.utf8)
            .write(to: openCode.appendingPathComponent("auth.json"))
        try Data(#"{"env":{"ANTHROPIC_BASE_URL":"https://api.z.ai/api/anthropic","ANTHROPIC_AUTH_TOKEN":"glm-key"}}"#.utf8)
            .write(to: claude.appendingPathComponent("settings.json"))

        let sources = PlanCredentialSources.load(home: home, environment: [:])
        XCTAssertEqual(ZaiPlan().credential(in: sources), PlanCredential(key: "glm-key", source: "Claude Code settings", host: ZaiPlan.globalHost))
        XCTAssertEqual(KimiPlan().credential(in: sources)?.key, "kimi-key")
        XCTAssertEqual(OpenCodeGoPlan().credential(in: sources)?.key, "go-key")
        XCTAssertNil(MiniMaxPlan().credential(in: sources))
        XCTAssertNil(CopilotPlan().credential(in: sources))
    }

    func testEnvironmentKeyWinsAndChinaVariablesPickTheChinaHost() {
        let sources = PlanCredentialSources(environment: ["GLM_API_KEY": "cn-key"])
        XCTAssertEqual(ZaiPlan().credential(in: sources), PlanCredential(key: "cn-key", source: "GLM_API_KEY", host: ZaiPlan.chinaHost))
    }

    // MARK: OpenCode Go credential precedence

    func testOpenCodeGoPrefersEnvironmentThenTheActiveAccountThenLegacyAuth() {
        let legacy = PlanCredentialSources(openCode: ["opencode": ["key": "legacy-key"]])
        XCTAssertEqual(OpenCodeGoPlan().credential(in: legacy), PlanCredential(key: "legacy-key", source: "OpenCode"))

        var account = legacy
        account.openCodeAccount = .account(token: "account-key", label: "Work")
        XCTAssertEqual(OpenCodeGoPlan().credential(in: account), PlanCredential(key: "account-key", source: "OpenCode · Work"))

        var env = account
        env.environment = ["OPENCODE_API_KEY": "env-key"]
        XCTAssertEqual(OpenCodeGoPlan().credential(in: env), PlanCredential(key: "env-key", source: "OPENCODE_API_KEY"))
    }

    func testAbsentConsentNeverRunsTheExportAndKeepsTheLegacyPath() {
        var exportCalls = 0
        let sources = PlanCredentialSources.load(
            home: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            environment: [:],
            accountUsageAllowed: false,
            accountExport: { _, _ in exportCalls += 1; return .account(token: "secret", label: "x") }
        )
        XCTAssertEqual(exportCalls, 0)
        XCTAssertNil(sources.openCodeAccount)
        XCTAssertNil(OpenCodeGoPlan().credential(in: sources))
    }

    func testConsentResolvesTheActiveAccountForTheGoPlan() {
        let sources = PlanCredentialSources.load(
            home: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            environment: [:],
            accountUsageAllowed: true,
            accountExport: { _, _ in .account(token: "active-key", label: "Default") }
        )
        XCTAssertEqual(sources.openCodeAccount, .account(token: "active-key", label: "Default"))
        XCTAssertEqual(OpenCodeGoPlan().credential(in: sources), PlanCredential(key: "active-key", source: "OpenCode · Default"))
    }
}

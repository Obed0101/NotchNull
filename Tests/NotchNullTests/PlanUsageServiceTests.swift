import SwiftUI
import XCTest
@testable import NotchNull

/// How `PlanUsageService.apply` turns provider results into shown state: a hidden provider without
/// a plan, the last good windows kept through a failed refresh, and sign-in guidance.
@MainActor
final class PlanUsageServiceTests: XCTestCase {
    private struct StubPlan: PlanProvider {
        var id = OpenCodeGoPlan.planID
        let title = "OpenCode Go"
        let monogram = "Go"
        var tint: Color { Theme.Accent.opencode }
        func credential(in sources: PlanCredentialSources) -> PlanCredential? { nil }
        func fetch(_ credential: PlanCredential) async throws -> PlanSnapshot { throw PlanError.unavailable("unused") }
    }

    private let credential = PlanCredential(key: "secret", source: "OpenCode · Default")
    private let windows = [UsageWindow(id: "opencode-rolling", label: "5 hours", percent: 5, resetsAt: nil, duration: 5 * 3600)]

    private func apply(_ service: PlanUsageService, _ outcome: Result<PlanSnapshot, PlanError>) {
        service.apply([(StubPlan(), credential, outcome)])
    }

    func testAReadyReadingStoresTheWindowsAndSource() {
        let service = PlanUsageService()
        apply(service, .success(PlanSnapshot(plan: nil, windows: windows)))
        XCTAssertEqual(service.usages.count, 1)
        XCTAssertEqual(service.usages.first?.state, .ready)
        XCTAssertEqual(service.usages.first?.windows, windows)
        XCTAssertEqual(service.usages.first?.source, "OpenCode · Default")
    }

    func testNoSubscriptionHidesTheProvider() {
        let service = PlanUsageService()
        apply(service, .failure(.noSubscription))
        XCTAssertTrue(service.usages.isEmpty)
    }

    func testSignedOutBeforeAnyReadingStaysHidden() {
        let service = PlanUsageService()
        apply(service, .failure(.signedOut("Key rejected by OpenCode")))
        XCTAssertTrue(service.usages.isEmpty)
    }

    func testTransientFailureKeepsTheLastGoodWindowsAndMarksThemUnavailable() {
        let service = PlanUsageService()
        apply(service, .success(PlanSnapshot(plan: "Go", windows: windows)))
        apply(service, .failure(.unavailable("Offline")))
        XCTAssertEqual(service.usages.count, 1)
        XCTAssertEqual(service.usages.first?.windows, windows)
        XCTAssertEqual(service.usages.first?.plan, "Go")
        XCTAssertEqual(service.usages.first?.state, .unavailable("Offline"))
    }

    func testSignedOutAfterAReadingShowsGuidanceWithoutBars() {
        let service = PlanUsageService()
        apply(service, .success(PlanSnapshot(plan: nil, windows: windows)))
        apply(service, .failure(.signedOut("Key rejected by OpenCode")))
        XCTAssertTrue(service.usages.first?.windows.isEmpty == true)
        XCTAssertEqual(service.usages.first?.state, .signedOut("Key rejected by OpenCode"))
    }
}

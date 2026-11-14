import AppKit
import XCTest
@testable import NotchNull

@MainActor
final class FullscreenConcealmentTests: XCTestCase {
    private func notchGeometry() -> NotchGeometry {
        NotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            notchSize: CGSize(width: 185, height: 32),
            hasHardwareNotch: true
        )
    }

    private func islandGeometry() -> NotchGeometry {
        NotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1800, height: 1125),
            notchSize: CGSize(width: Theme.Size.virtualNotch.width, height: 30),
            hasHardwareNotch: false
        )
    }

    private func withShape(_ style: Preferences.ShapeStyle, _ check: (String) throws -> Void) rethrows {
        let id = "TEST-\(UUID().uuidString)"
        let saved = Preferences.shared.displayShapes
        Preferences.shared.displayShapes[id] = Preferences.DisplayShape(style: style)
        defer { Preferences.shared.displayShapes = saved }
        try check(id)
    }

    private func withShapeAsync(_ style: Preferences.ShapeStyle, _ check: (String) async throws -> Void) async rethrows {
        let id = "TEST-\(UUID().uuidString)"
        let saved = Preferences.shared.displayShapes
        Preferences.shared.displayShapes[id] = Preferences.DisplayShape(style: style)
        defer { Preferences.shared.displayShapes = saved }
        try await check(id)
    }

    func testActivityFullscreenPresenceTable() {
        let alerts: Set<ActivityKind> = [
            .needsYou, .agentDone, .usageWarning, .timerFinished, .lowBattery,
            .downloadKeep, .downloadDone, .downloadTrashed, .screenshot,
        ]
        for kind in ActivityKind.allCases {
            let expected: FullscreenPresence = alerts.contains(kind) ? .alert : .hidden
            XCTAssertEqual(kind.fullscreenPresence, expected, "\(kind)")
        }
    }

    func testMostUrgentFindsAlertBehindAPersistentWinner() {
        let center = ActivityCenter()
        center.setPersistent(.custom, active: true)
        center.post(.agentDone, for: 60)
        XCTAssertEqual(center.current, .custom)
        XCTAssertEqual(center.mostUrgent { $0 == .agentDone }, .agentDone)
        XCTAssertNil(center.mostUrgent { $0 == .music })
        center.dismiss(.agentDone)
        center.setPersistent(.custom, active: false)
    }

    func testConcealmentPredicate() {
        let center = ActivityCenter()
        withShape(.notch) { id in
            let model = NotchViewModel(geometry: notchGeometry(), displayID: id, center: center)
            XCTAssertFalse(model.isConcealed)
            XCTAssertNil(model.revealReason)

            model.setFullscreenActive(true)
            XCTAssertTrue(model.isConcealed)
            XCTAssertNil(model.revealReason)

            model.isPointerInside = true
            XCTAssertFalse(model.isConcealed)
            XCTAssertEqual(model.revealReason, .hover)

            model.isPointerInside = false
            model.activityReveals = true
            XCTAssertFalse(model.isConcealed)
            XCTAssertEqual(model.revealReason, .activity)

            model.activityReveals = false
            XCTAssertTrue(model.isConcealed)
            model.open()
            XCTAssertFalse(model.isConcealed)
            XCTAssertEqual(model.revealReason, .open)

            model.close()
            XCTAssertTrue(model.isConcealed)
            model.setFullscreenActive(false)
            XCTAssertFalse(model.isConcealed)
        }
    }

    func testConcealOffsetForNotchAndIsland() {
        let margin = Theme.Size.fullscreenSlideMargin
        withShape(.notch) { id in
            let model = NotchViewModel(geometry: notchGeometry(), displayID: id, center: ActivityCenter())
            model.setFullscreenActive(true)
            XCTAssertTrue(model.isConcealed)
            XCTAssertEqual(model.concealOffset, -(model.bodyTop + model.shapeSize.height + margin))
        }

        let savedTop = Preferences.shared.islandTop
        Preferences.shared.islandTop = 8
        defer { Preferences.shared.islandTop = savedTop }
        withShape(.island) { id in
            let model = NotchViewModel(geometry: islandGeometry(), displayID: id, center: ActivityCenter())
            model.setFullscreenActive(true)
            XCTAssertTrue(model.isConcealed)
            XCTAssertGreaterThan(model.bodyTop, 0)
            XCTAssertEqual(model.concealOffset, -(model.bodyTop + model.shapeSize.height + margin))

            model.isPointerInside = true
            XCTAssertEqual(model.concealOffset, 0)
        }
    }

    func testWakeStripIsTheOnlyConcealedHitArea() {
        withShape(.notch) { id in
            let model = NotchViewModel(geometry: notchGeometry(), displayID: id, center: ActivityCenter())
            model.setFullscreenActive(true)
            let strip = model.wakeStripRect
            XCTAssertEqual(strip.height, Theme.Size.fullscreenWakeHeight, accuracy: 0.01)
            XCTAssertEqual(strip.width, model.closedSize.width, accuracy: 0.01)
            XCTAssertEqual(strip.midX, model.geometry.screenFrame.midX, accuracy: 0.01)
            XCTAssertEqual(strip.maxY, model.geometry.screenFrame.maxY, accuracy: 0.01)
            XCTAssertEqual(model.interactiveRect, strip)

            XCTAssertTrue(model.pointerMoved(to: CGPoint(x: strip.midX, y: strip.midY)))
            XCTAssertFalse(model.isConcealed)
            XCTAssertFalse(model.pointerMoved(to: CGPoint(x: strip.midX, y: strip.minY - 100)))
            XCTAssertTrue(model.isConcealed)
        }
    }

    func testConcealedDropProximityIsEmpty() {
        withShape(.notch) { id in
            let model = NotchViewModel(geometry: notchGeometry(), displayID: id, center: ActivityCenter())
            model.setFullscreenActive(true)
            XCTAssertTrue(model.dropProximityRect.isNull)
            model.isPointerInside = true
            XCTAssertFalse(model.dropProximityRect.isNull)
        }
    }

    func testFullscreenHoverOpensEvenWithClickTrigger() async {
        let savedTrigger = Preferences.shared.openTrigger
        let savedClose = Preferences.shared.closeDelay
        let savedAlerts = Preferences.shared.revealAlertsOnFullscreen
        Preferences.shared.openTrigger = .click
        Preferences.shared.closeDelay = 0.2
        Preferences.shared.revealAlertsOnFullscreen = true
        defer {
            Preferences.shared.openTrigger = savedTrigger
            Preferences.shared.closeDelay = savedClose
            Preferences.shared.revealAlertsOnFullscreen = savedAlerts
        }

        await withShapeAsync(.notch) { id in
            let model = NotchViewModel(geometry: notchGeometry(), displayID: id, center: ActivityCenter())
            model.setFullscreenActive(true)
            let strip = model.wakeStripRect
            XCTAssertTrue(model.pointerMoved(to: CGPoint(x: strip.midX, y: strip.midY)))
            try? await Task.sleep(for: .milliseconds(250))
            XCTAssertEqual(model.phase, .open)
            XCTAssertFalse(model.isConcealed)

            XCTAssertFalse(model.pointerMoved(to: CGPoint(x: strip.midX, y: strip.minY - 400)))
            try? await Task.sleep(for: .milliseconds(450))
            XCTAssertEqual(model.phase, .closed)
            XCTAssertTrue(model.isConcealed)
        }
    }

    func testSettingsFileAppliesRevealAlerts() {
        let saved = Preferences.shared.revealAlertsOnFullscreen
        defer { Preferences.shared.revealAlertsOnFullscreen = saved }
        let errors = SettingsFile.shared.apply(
            Data(#"{"behavior":{"revealAlertsOnFullscreen":false}}"#.utf8), isPatch: true
        )
        XCTAssertTrue(errors.isEmpty)
        XCTAssertFalse(Preferences.shared.revealAlertsOnFullscreen)
        XCTAssertEqual(SettingsFile.shared.snapshot().value(at: "behavior.revealAlertsOnFullscreen")?.bool, false)
    }

    func testTransientAlertRevealsThenConcealsOnExpiry() async {
        let saved = Preferences.shared.revealAlertsOnFullscreen
        Preferences.shared.revealAlertsOnFullscreen = true
        defer { Preferences.shared.revealAlertsOnFullscreen = saved }

        let center = ActivityCenter()
        center.post(.agentDone, for: 0.2)
        await withShapeAsync(.notch) { id in
            let model = NotchViewModel(geometry: notchGeometry(), displayID: id, center: center)
            model.setFullscreenActive(true)
            try? await Task.sleep(for: .milliseconds(120))
            XCTAssertFalse(model.isConcealed)
            try? await Task.sleep(for: .milliseconds(350))
            XCTAssertTrue(model.isConcealed)
        }
        center.dismiss(.agentDone)
    }

    func testAlertExpiryBehindAPersistentWinnerReconceals() async {
        let saved = Preferences.shared.revealAlertsOnFullscreen
        Preferences.shared.revealAlertsOnFullscreen = true
        defer { Preferences.shared.revealAlertsOnFullscreen = saved }

        let center = ActivityCenter()
        center.setPersistent(.custom, active: true)
        center.post(.agentDone, for: 0.2)
        await withShapeAsync(.notch) { id in
            let model = NotchViewModel(geometry: notchGeometry(), displayID: id, center: center)
            model.setFullscreenActive(true)
            try? await Task.sleep(for: .milliseconds(120))
            XCTAssertFalse(model.isConcealed)
            XCTAssertTrue(model.activityReveals)

            try? await Task.sleep(for: .milliseconds(350))
            XCTAssertTrue(model.isConcealed)
            XCTAssertFalse(model.activityReveals)
        }
        center.dismiss(.agentDone)
        center.setPersistent(.custom, active: false)
    }

    func testSatelliteHitRectsDisappearWhileConcealed() {
        let savedSatellites = Preferences.shared.islandSatellites
        Preferences.shared.islandSatellites = true
        defer { Preferences.shared.islandSatellites = savedSatellites }
        withShape(.island) { id in
            let model = NotchViewModel(geometry: islandGeometry(), displayID: id, center: ActivityCenter())
            XCTAssertFalse(model.satelliteScreenRects.isEmpty)
            model.setFullscreenActive(true)
            XCTAssertTrue(model.isConcealed)
            XCTAssertTrue(model.satelliteScreenRects.isEmpty)
            model.isPointerInside = true
            XCTAssertFalse(model.isConcealed)
            XCTAssertFalse(model.satelliteScreenRects.isEmpty)
        }
    }

    func testTransientCustomRevealsAndPersistentCustomStaysConcealed() async {
        let saved = Preferences.shared.revealAlertsOnFullscreen
        Preferences.shared.revealAlertsOnFullscreen = true
        defer { Preferences.shared.revealAlertsOnFullscreen = saved }

        let center = ActivityCenter()
        let store = CustomActivityStore(center: center, writesStatus: false)
        try? await withShapeAsync(.notch) { id in
            let model = NotchViewModel(geometry: notchGeometry(), displayID: id, center: center, customActivities: store)
            model.setFullscreenActive(true)
            XCTAssertTrue(model.isConcealed)

            let transient = try XCTUnwrap(CustomActivity(payload: .object([
                "id": .string("test-transient"),
                "symbol": .string("bell.fill"),
                "duration": .number(60),
            ])))
            store.set(transient)
            try? await Task.sleep(for: .milliseconds(120))
            XCTAssertTrue(model.activityReveals)
            XCTAssertFalse(model.isConcealed)

            let persistent = try XCTUnwrap(CustomActivity(payload: .object([
                "id": .string("test-persistent"),
                "symbol": .string("gear"),
                "persistent": .bool(true),
            ])))
            store.set(persistent)
            try? await Task.sleep(for: .milliseconds(120))
            XCTAssertFalse(model.activityReveals)
            XCTAssertTrue(model.isConcealed)
            store.removeAll()
        }
    }

    func testRevealAlertsSettingGatesAutomaticReveal() async {
        let saved = Preferences.shared.revealAlertsOnFullscreen
        defer { Preferences.shared.revealAlertsOnFullscreen = saved }
        Preferences.shared.revealAlertsOnFullscreen = false

        let center = ActivityCenter()
        center.post(.agentDone, for: 60)
        await withShapeAsync(.notch) { id in
            let model = NotchViewModel(geometry: notchGeometry(), displayID: id, center: center)
            model.setFullscreenActive(true)
            try? await Task.sleep(for: .milliseconds(120))
            XCTAssertFalse(model.activityReveals)
            XCTAssertTrue(model.isConcealed)

            Preferences.shared.revealAlertsOnFullscreen = true
            try? await Task.sleep(for: .milliseconds(120))
            XCTAssertTrue(model.activityReveals)
            XCTAssertFalse(model.isConcealed)
        }
        center.dismiss(.agentDone)
    }
}

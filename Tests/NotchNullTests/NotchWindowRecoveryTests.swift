import AppKit
import XCTest
@testable import NotchNull

@MainActor
final class NotchWindowRecoveryTests: XCTestCase {
    private func resetSharedActivities() async {
        for kind in ActivityKind.allCases { ActivityCenter.shared.dismiss(kind) }
        try? await Task.sleep(for: .milliseconds(60))
    }

    private func withController(onWindowFailure: (() -> Void)? = nil,
        _ check: (NotchWindowController, NotchPanel) async -> Void) async throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first else { throw XCTSkip("Requires a display") }
        let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
        let services = AppServices() // Do not start services or request permissions.
        let controller = NotchWindowController(screen: screen, services: services, onWindowFailure: onWindowFailure)
        defer { controller.tearDown() }
        let panel = try XCTUnwrap(NSApp.windows.compactMap { $0 as? NotchPanel }
            .first { !existing.contains(ObjectIdentifier($0)) })
        await check(controller, panel)
    }

    /// Same fixture, with the shared services so a test can inspect long-lived state such as the clock.
    private func withControllerAndServices(
        _ check: (NotchWindowController, NotchPanel, AppServices) async -> Void) async throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first else { throw XCTSkip("Requires a display") }
        let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
        let services = AppServices()
        let controller = NotchWindowController(screen: screen, services: services)
        defer { controller.tearDown() }
        let panel = try XCTUnwrap(NSApp.windows.compactMap { $0 as? NotchPanel }
            .first { !existing.contains(ObjectIdentifier($0)) })
        await check(controller, panel, services)
    }

    func testExplicitOpenRestoresAnOrderedOutPanelWithoutTakingKeyboardFocus() async throws {
        try await withController { controller, panel in
            panel.orderOut(nil)
            XCTAssertFalse(panel.isVisible)
            controller.open(tab: .home)
            XCTAssertTrue(panel.isVisible)
            XCTAssertFalse(panel.isKeyWindow)
            XCTAssertEqual(controller.model.phase, .open)
        }
    }

    func testVisibilityReconciliationRestoresAnOrderedOutPanel() async throws {
        try await withController { controller, panel in
            panel.orderOut(nil)
            controller.setFullscreenActive(false)
            XCTAssertTrue(panel.isVisible)
        }
    }

    func testReconciliationReturnsADisplacedPanelToItsDisplay() async throws {
        try await withController { controller, panel in
            let expected = controller.model.geometry.windowFrame
            panel.setFrameOrigin(NSPoint(x: expected.minX - 4000, y: expected.minY))
            controller.setFullscreenActive(false)
            XCTAssertEqual(panel.frame, expected)
            XCTAssertTrue(panel.isVisible)
        }
    }

    func testFullscreenKeepsThePanelRegisteredAndExplicitOpenRevealsIt() async throws {
        try await withController { controller, panel in
            await resetSharedActivities()
            controller.setFullscreenActive(true)
            XCTAssertTrue(panel.isVisible)
            XCTAssertTrue(controller.isFullscreenActive)
            XCTAssertTrue(controller.model.isConcealed)
            XCTAssertFalse(controller.model.isWindowVisible)

            controller.open(tab: .home)
            XCTAssertTrue(panel.isVisible)
            XCTAssertFalse(controller.model.isConcealed)
            XCTAssertEqual(controller.model.phase, .open)

            controller.model.close()
            controller.toggleClipboardFromKeyboard()
            XCTAssertTrue(panel.isVisible)
            XCTAssertFalse(controller.model.isConcealed)
            XCTAssertEqual(controller.model.selectedTab, .clipboard)

            controller.setFullscreenActive(false)
            XCTAssertFalse(controller.model.isConcealed)
            XCTAssertTrue(panel.isVisible)
        }
    }

    func testWindowStatusReportsFullscreenConcealment() async throws {
        try await withController { controller, _ in
            await resetSharedActivities()
            controller.setFullscreenActive(true)
            var status = controller.windowStatus.object ?? [:]
            XCTAssertEqual(status["fullscreen"]?.bool, true)
            XCTAssertEqual(status["concealed"]?.bool, true)
            XCTAssertEqual(status["fullscreenHidden"]?.bool, true)
            XCTAssertNil(status["reveal"]?.string)

            controller.model.activityReveals = true
            status = controller.windowStatus.object ?? [:]
            XCTAssertEqual(status["concealed"]?.bool, false)
            XCTAssertEqual(status["reveal"]?.string, "activity")

            controller.model.isPointerInside = true
            status = controller.windowStatus.object ?? [:]
            XCTAssertEqual(status["reveal"]?.string, "hover")

            controller.setFullscreenActive(false)
            status = controller.windowStatus.object ?? [:]
            XCTAssertEqual(status["fullscreen"]?.bool, false)
            XCTAssertEqual(status["concealed"]?.bool, false)
        }
    }

    func testClipboardShortcutRestoresAnOrderedOutPanel() async throws {
        try await withController { controller, panel in
            panel.orderOut(nil)
            controller.toggleClipboardFromKeyboard()
            XCTAssertTrue(panel.isVisible)
            XCTAssertEqual(controller.model.selectedTab, .clipboard)
        }
    }

    func testUnexpectedOrderingOutRecoversWithoutAnOpenCommand() async throws {
        try await withController { _, panel in
            panel.orderOut(nil)
            XCTAssertFalse(panel.isVisible)
            try? await Task.sleep(for: .seconds(Constants.Intervals.fullscreenPoll + 0.5))
            XCTAssertTrue(panel.isVisible)
        }
    }

    func testTearingDownAPanelCancelsAutomaticRecovery() async throws {
        try await withController { controller, panel in
            controller.tearDown()
            try? await Task.sleep(for: .seconds(Constants.Intervals.fullscreenPoll + 0.5))
            XCTAssertFalse(panel.isVisible)
        }
    }

    func testFailedWindowServerRecoveryRequestsReplacementOnce() async throws {
        var replacements = 0
        try await withController(onWindowFailure: { replacements += 1 }) { controller, panel in
            controller.open(tab: .agents)
            // The captured failure: AppKit has an ordered window, Window Server cannot show it.
            XCTAssertTrue(panel.isVisible)
            controller.reconcileWindowVisibility(isOnScreen: false)
            XCTAssertEqual(replacements, 0)
            controller.reconcileWindowVisibility(isOnScreen: false)
            XCTAssertEqual(replacements, 1)
            controller.reconcileWindowVisibility(isOnScreen: false)
            XCTAssertEqual(replacements, 1)
            XCTAssertEqual(controller.model.selectedTab, .agents)
            controller.reconcileWindowVisibility(isOnScreen: true)
            controller.reconcileWindowVisibility(isOnScreen: false)
            controller.reconcileWindowVisibility(isOnScreen: false)
            XCTAssertEqual(replacements, 2)
        }
    }

    func testUnknownWindowServerStateIsIgnoredButFullscreenStillRecovers() async throws {
        var replacements = 0
        try await withController(onWindowFailure: { replacements += 1 }) { controller, _ in
            controller.reconcileWindowVisibility(isOnScreen: nil)
            controller.reconcileWindowVisibility(isOnScreen: nil)
            XCTAssertEqual(replacements, 0)

            controller.setFullscreenActive(true)
            controller.reconcileWindowVisibility(isOnScreen: false)
            XCTAssertEqual(replacements, 0)
            controller.reconcileWindowVisibility(isOnScreen: false)
            XCTAssertEqual(replacements, 1)
        }
    }

    func testReplacementUsesTheSamePresentationModel() async throws {
        try await withController { controller, _ in
            guard let screen = NSScreen.screens.first else { return XCTFail("Missing display") }
            controller.open(tab: .agents)
            let model = controller.model
            controller.tearDown()
            let replacement = NotchWindowController(screen: screen, services: AppServices(), model: model)
            defer { replacement.tearDown() }
            XCTAssertTrue(replacement.model === model)
            XCTAssertEqual(replacement.model.selectedTab, .agents)
            XCTAssertEqual(replacement.model.phase, .open)
        }
    }

    func testClockPausesWhenTheNotchIsNotVisibleAndResumesWhenRestored() async throws {
        try await withControllerAndServices { controller, panel, services in
            await resetSharedActivities()
            // The clock ticks only while a time label shows in a visible window.
            services.clock.setShowing(true, label: UUID())
            controller.reconcileWindowVisibility(isOnScreen: true)
            XCTAssertEqual(services.clock.activeConsumers, 1)
            XCTAssertTrue(services.clock.isRunning)

            controller.setFullscreenActive(true)
            XCTAssertFalse(controller.model.isWindowVisible)
            XCTAssertEqual(services.clock.activeConsumers, 0)
            XCTAssertFalse(services.clock.isRunning)

            controller.setFullscreenActive(false)
            controller.reconcileWindowVisibility(isOnScreen: true)
            XCTAssertTrue(controller.model.isWindowVisible)
            XCTAssertEqual(services.clock.activeConsumers, 1)
            XCTAssertTrue(services.clock.isRunning)

            panel.orderOut(nil)
            for _ in 0..<20 where services.clock.activeConsumers == 1 {
                try? await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertEqual(services.clock.activeConsumers, 0)

            controller.setFullscreenActive(false)
            controller.reconcileWindowVisibility(isOnScreen: true)
            XCTAssertEqual(services.clock.activeConsumers, 1)
        }
    }

    func testDisplaySleepAndAppHidingPauseTheClock() async throws {
        try await withControllerAndServices { controller, _, services in
            controller.reconcileWindowVisibility(isOnScreen: true)
            XCTAssertEqual(services.clock.activeConsumers, 1)

            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
            XCTAssertFalse(controller.model.isWindowVisible)
            XCTAssertEqual(services.clock.activeConsumers, 0)

            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
            controller.reconcileWindowVisibility(isOnScreen: true)
            XCTAssertTrue(controller.model.isWindowVisible)
            XCTAssertEqual(services.clock.activeConsumers, 1)

            NotificationCenter.default.post(name: NSApplication.didHideNotification, object: NSApp)
            XCTAssertFalse(controller.model.isWindowVisible)
            XCTAssertEqual(services.clock.activeConsumers, 0)

            NotificationCenter.default.post(name: NSApplication.didUnhideNotification, object: NSApp)
            controller.reconcileWindowVisibility(isOnScreen: true)
            XCTAssertTrue(controller.model.isWindowVisible)
            XCTAssertEqual(services.clock.activeConsumers, 1)
        }
    }

    func testTwoWindowsShareOneClockAndHiddenWindowsReleaseIt() async throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first else { throw XCTSkip("Requires a display") }
        let services = AppServices()
        let first = NotchWindowController(screen: screen, services: services)
        let second = NotchWindowController(screen: screen, services: services)
        defer {
            first.tearDown()
            second.tearDown()
        }
        await resetSharedActivities()
        services.clock.setShowing(true, label: UUID())
        first.reconcileWindowVisibility(isOnScreen: true)
        second.reconcileWindowVisibility(isOnScreen: true)
        XCTAssertEqual(services.clock.activeConsumers, 2)
        XCTAssertTrue(services.clock.isRunning)

        first.setFullscreenActive(true)
        XCTAssertEqual(services.clock.activeConsumers, 1)
        XCTAssertTrue(second.model.isWindowVisible)

        second.setFullscreenActive(true)
        XCTAssertEqual(services.clock.activeConsumers, 0)
        XCTAssertFalse(services.clock.isRunning)

        first.setFullscreenActive(false)
        first.reconcileWindowVisibility(isOnScreen: true)
        XCTAssertEqual(services.clock.activeConsumers, 1)
        XCTAssertTrue(services.clock.isRunning)
    }

    func testSamplingTracksRealPhaseTabAndWindowRatherThanAppearances() async throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first else { throw XCTSkip("Requires display") }
        let services = AppServices()
        let controller = NotchWindowController(screen: screen, services: services)
        defer { controller.tearDown() }
        await resetSharedActivities()
        controller.open(tab: .home)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(controller.model.phase, .open)
        XCTAssertEqual(controller.model.visibleTab, .home)
        controller.reconcileWindowVisibility(isOnScreen: true)
        XCTAssertEqual(services.stats.isSampling, Preferences.shared.statsEnabled)
        controller.model.select(.agents)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(services.stats.isSampling)
        controller.open(tab: .home)
        try? await Task.sleep(for: .milliseconds(100))
        controller.model.close()
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(services.stats.isSampling)
        controller.open(tab: .home)
        try? await Task.sleep(for: .milliseconds(100))
        controller.setFullscreenActive(true)
        XCTAssertFalse(services.stats.isSampling)
        XCTAssertFalse(controller.model.isWindowVisible)
        XCTAssertEqual(services.clock.activeConsumers, 0)
        controller.setFullscreenActive(false)
        controller.open(tab: .home)
        try? await Task.sleep(for: .milliseconds(100))
        controller.reconcileWindowVisibility(isOnScreen: true)
        XCTAssertEqual(services.stats.isSampling, Preferences.shared.statsEnabled)
        XCTAssertEqual(services.clock.activeConsumers, 1)
        controller.tearDown()
        XCTAssertFalse(services.stats.isSampling)
        XCTAssertEqual(services.clock.activeConsumers, 0)
    }
}

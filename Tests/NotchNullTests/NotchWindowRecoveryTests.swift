import AppKit
import XCTest
@testable import NotchNull

@MainActor
final class NotchWindowRecoveryTests: XCTestCase {
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
            controller.setFullscreenHidden(false)
            XCTAssertTrue(panel.isVisible)
        }
    }

    func testReconciliationReturnsADisplacedPanelToItsDisplay() async throws {
        try await withController { controller, panel in
            let expected = controller.model.geometry.windowFrame
            panel.setFrameOrigin(NSPoint(x: expected.minX - 4000, y: expected.minY))
            controller.setFullscreenHidden(false)
            XCTAssertEqual(panel.frame, expected)
            XCTAssertTrue(panel.isVisible)
        }
    }

    func testRecoveryNeverShowsThePanelWhileFullscreenHidingIsActive() async throws {
        try await withController { controller, panel in
            controller.setFullscreenHidden(true)
            controller.open(tab: .home)
            controller.toggleClipboardFromKeyboard()
            controller.setFullscreenHidden(true)
            try? await Task.sleep(for: .seconds(Constants.Intervals.fullscreenPoll + 0.5))
            XCTAssertFalse(panel.isVisible)
            XCTAssertFalse(panel.isKeyWindow)
            XCTAssertTrue(controller.isFullscreenHidden)
            controller.setFullscreenHidden(false)
            XCTAssertTrue(panel.isVisible)
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

    func testUnknownWindowServerStateAndFullscreenNeverRequestReplacement() async throws {
        var replacements = 0
        try await withController(onWindowFailure: { replacements += 1 }) { controller, _ in
            controller.reconcileWindowVisibility(isOnScreen: nil)
            controller.reconcileWindowVisibility(isOnScreen: nil)
            controller.setFullscreenHidden(true)
            controller.reconcileWindowVisibility(isOnScreen: false)
            controller.reconcileWindowVisibility(isOnScreen: false)
            XCTAssertEqual(replacements, 0)
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
}

import XCTest
@testable import NotchNull

@MainActor
final class NotchRenderBudgetTests: XCTestCase {
    func testChasingOutlineRunsOnlyForAVisibleNeedsYouActivity() {
        XCTAssertTrue(ChasingOutline.isActive(phase: .activity(.needsYou), visible: true, glowEnabled: true))
        // A body concealed for fullscreen has isWindowVisible=false, so even a needs-you activity
        // must not keep its outline running off screen.
        XCTAssertFalse(ChasingOutline.isActive(phase: .activity(.needsYou), visible: false, glowEnabled: true))
        XCTAssertFalse(ChasingOutline.isActive(phase: .activity(.needsYou), visible: true, glowEnabled: false))
        XCTAssertFalse(ChasingOutline.isActive(phase: .closed, visible: true, glowEnabled: true))
        XCTAssertFalse(ChasingOutline.isActive(phase: .activity(.music), visible: true, glowEnabled: true))
    }
}

import XCTest
@testable import NotchNull

@MainActor
final class DisplaySelectionTests: XCTestCase {
    private let mac = NotchDisplay(id: 1, persistentID: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", name: "MacBook", frame: CGRect(x: 0, y: 0, width: 1800, height: 1125), builtIn: true, hasNotch: false, scale: 2)
    private let monitor = NotchDisplay(id: 2, persistentID: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", name: "HP 23er", frame: CGRect(x: -1920, y: 300, width: 1920, height: 1080), builtIn: false, hasNotch: false, scale: 1)
    private let ipad = NotchDisplay(id: 3, persistentID: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC", name: "iPad", frame: CGRect(x: 1800, y: -200, width: 1024, height: 768), builtIn: false, hasNotch: false, scale: 2)

    func testDisplayModesAndClamshellFallback() {
        let screens = [monitor, mac, ipad]
        XCTAssertEqual(DisplaySelection.eligible(screens, mode: .all, selected: []), screens)
        XCTAssertEqual(DisplaySelection.eligible(screens, mode: .main, selected: []), [monitor])
        XCTAssertEqual(DisplaySelection.eligible(screens, mode: .builtIn, selected: []), [mac])
        XCTAssertEqual(DisplaySelection.eligible([monitor, ipad], mode: .builtIn, selected: []), [monitor])
        XCTAssertTrue(DisplaySelection.eligible([], mode: .main, selected: []).isEmpty)
    }

    func testSelectionSurvivesReconnectWithDifferentRuntimeID() {
        let reconnected = NotchDisplay(id: 99, persistentID: monitor.persistentID, name: monitor.name, frame: monitor.frame, builtIn: false, hasNotch: false, scale: 1)
        let selected = [monitor.persistentID, ipad.persistentID]
        XCTAssertEqual(DisplaySelection.eligible([mac, ipad], mode: .selected, selected: selected), [ipad])
        XCTAssertEqual(DisplaySelection.eligible([mac, reconnected, ipad], mode: .selected, selected: selected), [reconnected, ipad])
        XCTAssertTrue(DisplaySelection.eligible([mac, monitor, ipad], mode: .selected, selected: []).isEmpty)
    }

    func testShortcutFollowsPointerIncludingNegativeOrigins() {
        let screens = [mac, monitor, ipad]
        XCTAssertEqual(DisplaySelection.target(screens, pointer: CGPoint(x: -500, y: 600)), monitor.id)
        XCTAssertEqual(DisplaySelection.target(screens, pointer: CGPoint(x: 2000, y: 100)), ipad.id)
        XCTAssertEqual(DisplaySelection.target(screens, pointer: CGPoint(x: 100, y: 100)), mac.id)
        XCTAssertEqual(DisplaySelection.target(screens, pointer: CGPoint(x: 9000, y: 9000)), mac.id)
        XCTAssertNil(DisplaySelection.target([], pointer: .zero))
    }

    func testGeometryIsPinnedToEachDisplayNotTheMainOrigin() {
        for display in [mac, monitor, ipad] {
            let geometry = NotchGeometry(screenFrame: display.frame, notchSize: CGSize(width: 190, height: 24), hasHardwareNotch: false)
            XCTAssertEqual(geometry.windowFrame.midX, display.frame.midX)
            XCTAssertEqual(geometry.windowFrame.maxY, display.frame.maxY)
            let body = geometry.bodyRect(for: CGSize(width: 500, height: 200), top: 2)
            XCTAssertEqual(body.midX, display.frame.midX)
            XCTAssertEqual(body.maxY, display.frame.maxY - 2)
        }
    }

    func testSettingsRejectInvalidSelectionWithoutDiscardingSavedDisplays() {
        let prefs = Preferences.shared
        let savedMode = prefs.displayMode
        let savedDisplays = prefs.selectedDisplays
        defer { prefs.displayMode = savedMode; prefs.selectedDisplays = savedDisplays }
        let valid = Data("{\"behavior\":{\"display\":\"selected\",\"selectedDisplays\":[\"\(monitor.persistentID.lowercased())\"]}}".utf8)
        XCTAssertTrue(SettingsFile.shared.apply(valid, isPatch: true).isEmpty)
        XCTAssertEqual(prefs.displayMode, .selected)
        XCTAssertEqual(prefs.selectedDisplays, [monitor.persistentID])
        for invalid in ["[12]", "[\"invalid\"]", "null", "\"not a list\""] {
            let errors = SettingsFile.shared.apply(Data("{\"behavior\":{\"selectedDisplays\":\(invalid)}}".utf8), isPatch: true)
            XCTAssertFalse(errors.isEmpty)
            XCTAssertEqual(prefs.selectedDisplays, [monitor.persistentID])
        }
    }
}

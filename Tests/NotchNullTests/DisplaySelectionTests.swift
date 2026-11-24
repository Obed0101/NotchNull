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

    func testAttentionFollowsSingleDisplayMode() {
        let screens = [monitor, mac, ipad]
        XCTAssertEqual(
            DisplaySelection.attentionEligible(screens, displayMode: .main, selected: [],
                attentionMode: .followDisplay, attentionSelected: []),
            [monitor]
        )
        XCTAssertEqual(
            DisplaySelection.attentionEligible(screens, displayMode: .selected, selected: [ipad.persistentID, monitor.persistentID],
                attentionMode: .followDisplay, attentionSelected: []),
            [monitor]
        )
        XCTAssertEqual(
            DisplaySelection.attentionEligible(screens, displayMode: .all, selected: [],
                attentionMode: .followDisplay, attentionSelected: []),
            screens
        )
        XCTAssertEqual(
            DisplaySelection.attentionEligible([ipad, monitor], displayMode: .builtIn, selected: [],
                attentionMode: .followDisplay, attentionSelected: []),
            [ipad]
        )
    }

    func testAttentionSelectionIsAlwaysASubsetOfNotchEnabledDisplays() {
        let screens = [monitor, mac, ipad]
        XCTAssertEqual(
            DisplaySelection.attentionEligible(screens, displayMode: .all, selected: [],
                attentionMode: .enabled, attentionSelected: []),
            screens
        )
        XCTAssertEqual(
            DisplaySelection.attentionEligible(screens, displayMode: .selected, selected: [monitor.persistentID, ipad.persistentID],
                attentionMode: .enabled, attentionSelected: []),
            [monitor, ipad]
        )
        XCTAssertEqual(
            DisplaySelection.attentionEligible(screens, displayMode: .selected, selected: [monitor.persistentID],
                attentionMode: .selected, attentionSelected: screens.map(\.persistentID)),
            [monitor]
        )
        XCTAssertTrue(
            DisplaySelection.attentionEligible(screens, displayMode: .builtIn, selected: [],
                attentionMode: .selected, attentionSelected: [monitor.persistentID]).isEmpty
        )
        XCTAssertTrue(
            DisplaySelection.attentionEligible(screens, displayMode: .selected, selected: [],
                attentionMode: .selected, attentionSelected: [monitor.persistentID]).isEmpty
        )
    }

    func testAttentionSelectionSurvivesReconnectAndMainDisplayChanges() {
        let reconnected = NotchDisplay(id: 99, persistentID: monitor.persistentID, name: monitor.name, frame: monitor.frame, builtIn: false, hasNotch: false, scale: 1)
        let selected = [monitor.persistentID]
        XCTAssertTrue(DisplaySelection.allowsAttention(
            displayID: monitor.persistentID, displays: [mac, reconnected], displayMode: .selected,
            selected: [monitor.persistentID], attentionMode: .selected, attentionSelected: selected,
            connected: [mac, reconnected]
        ))
        XCTAssertEqual(
            DisplaySelection.attentionEligible([mac, ipad], displayMode: .main, selected: [],
                attentionMode: .enabled, attentionSelected: [], connected: [monitor, mac, ipad]),
            [monitor]
        )
        XCTAssertEqual(
            DisplaySelection.attentionEligible([ipad, mac], displayMode: .main, selected: [],
                attentionMode: .enabled, attentionSelected: [], connected: [monitor, mac, ipad]),
            [monitor]
        )
        let reordered = [ipad, monitor, mac]
        XCTAssertEqual(
            DisplaySelection.attentionEligible([mac, ipad], displayMode: .main, selected: [],
                attentionMode: .enabled, attentionSelected: [], connected: reordered),
            [ipad]
        )
    }

    func testAttentionSelectionPrunesOnlyActivelyDisabledDisplays() {
        let screens = [monitor, mac, ipad]
        let saved = [monitor.persistentID, mac.persistentID.lowercased(), ipad.persistentID,
                     "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD"]
        XCTAssertEqual(
            DisplaySelection.pruneAttention(saved, displays: screens, displayMode: .selected, selected: [monitor.persistentID.lowercased(), ipad.persistentID]),
            [monitor.persistentID, ipad.persistentID, "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD"]
        )
        XCTAssertEqual(
            DisplaySelection.pruneAttention(saved, displays: screens, displayMode: .selected, selected: [monitor.persistentID]),
            [monitor.persistentID, "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD"]
        )
        XCTAssertEqual(
            DisplaySelection.pruneAttention(saved, displays: screens, displayMode: .all, selected: []),
            saved
        )
        XCTAssertEqual(
            DisplaySelection.pruneAttention(saved, displays: screens, displayMode: .main, selected: []),
            saved
        )
        XCTAssertEqual(
            DisplaySelection.pruneAttention(saved, displays: screens, displayMode: .builtIn, selected: []),
            saved
        )
    }

    func testAttentionSettingsRoundTripAndRejectInvalidUUIDs() {
        let prefs = Preferences.shared
        let savedMode = prefs.attentionDisplayMode
        let savedDisplays = prefs.attentionDisplays
        defer { prefs.attentionDisplayMode = savedMode; prefs.attentionDisplays = savedDisplays }

        let valid = Data("{\"behavior\":{\"attentionDisplay\":\"selected\",\"attentionDisplays\":[\"\(monitor.persistentID.lowercased())\",\"\(monitor.persistentID)\"]}}".utf8)
        XCTAssertTrue(SettingsFile.shared.apply(valid, isPatch: true).isEmpty)
        XCTAssertEqual(prefs.attentionDisplayMode, .selected)
        XCTAssertEqual(prefs.attentionDisplays, [monitor.persistentID])
        XCTAssertEqual(SettingsFile.shared.snapshot().value(at: "behavior.attentionDisplay")?.string, "selected")
        XCTAssertEqual(SettingsFile.shared.snapshot().value(at: "behavior.attentionDisplays")?.array?.count, 1)

        for invalid in ["[12]", "[\"invalid\"]", "null", "\"not a list\""] {
            let errors = SettingsFile.shared.apply(Data("{\"behavior\":{\"attentionDisplays\":\(invalid)}}".utf8), isPatch: true)
            XCTAssertFalse(errors.isEmpty)
            XCTAssertEqual(prefs.attentionDisplays, [monitor.persistentID])
        }
        let badMode = SettingsFile.shared.apply(Data(#"{"behavior":{"attentionDisplay":"some"}}"#.utf8), isPatch: true)
        XCTAssertFalse(badMode.isEmpty)
        XCTAssertEqual(prefs.attentionDisplayMode, .selected)

        let followErrors = SettingsFile.shared.apply(Data(#"{"behavior":{"attentionDisplay":"followDisplay"}}"#.utf8), isPatch: true)
        XCTAssertTrue(followErrors.isEmpty)
        XCTAssertEqual(prefs.attentionDisplayMode, .followDisplay)
    }

    func testDirectNotchToggleSeedsAndSwitchesToCustom() {
        let screens = [monitor, mac, ipad]

        let allOff = DisplaySelection.togglingNotch(
            monitor, enabled: false, displays: screens, mode: .all, selected: [])
        XCTAssertEqual(allOff.mode, .selected)
        XCTAssertEqual(allOff.selected, [mac.persistentID, ipad.persistentID])

        let disconnected = "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD"
        let remembered = DisplaySelection.togglingNotch(
            monitor, enabled: false, displays: screens, mode: .all, selected: [disconnected])
        XCTAssertEqual(remembered.selected, [disconnected, mac.persistentID, ipad.persistentID])

        let mainOn = DisplaySelection.togglingNotch(
            ipad, enabled: true, displays: screens, mode: .main, selected: [])
        XCTAssertEqual(mainOn.mode, .selected)
        XCTAssertEqual(mainOn.selected, [monitor.persistentID, ipad.persistentID])

        let builtInOff = DisplaySelection.togglingNotch(
            mac, enabled: false, displays: screens, mode: .builtIn, selected: [])
        XCTAssertEqual(builtInOff.mode, .selected)
        XCTAssertTrue(builtInOff.selected.isEmpty)

        let customOff = DisplaySelection.togglingNotch(
            monitor, enabled: false, displays: screens, mode: .selected,
            selected: [monitor.persistentID.lowercased(), ipad.persistentID])
        XCTAssertEqual(customOff.mode, .selected)
        XCTAssertEqual(customOff.selected, [ipad.persistentID])
    }

    func testNotchToggleMakesDisabledDisplayDiscoverableAgain() {
        let screens = [monitor, mac, ipad]
        let onlyMonitor = DisplaySelection.togglingNotch(
            ipad, enabled: false, displays: screens, mode: .selected,
            selected: [monitor.persistentID, ipad.persistentID])
        XCTAssertEqual(DisplaySelection.eligible(screens, mode: .selected, selected: onlyMonitor.selected), [monitor])

        let backOn = DisplaySelection.togglingNotch(
            ipad, enabled: true, displays: screens, mode: onlyMonitor.mode, selected: onlyMonitor.selected)
        XCTAssertEqual(backOn.mode, .selected)
        XCTAssertEqual(backOn.selected, [monitor.persistentID, ipad.persistentID])
    }

    func testAttentionToggleSeedsEffectiveTargetsAndSwitchesToSelected() {
        let screens = [monitor, mac, ipad]

        let allOff = DisplaySelection.togglingAttention(
            ipad, enabled: false, displays: screens, displayMode: .all, selected: [],
            attentionMode: .enabled, attentionSelected: [])
        XCTAssertEqual(allOff.mode, .selected)
        XCTAssertEqual(allOff.selected, [monitor.persistentID, mac.persistentID])

        let disconnected = "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD"
        let remembered = DisplaySelection.togglingAttention(
            ipad, enabled: false, displays: screens, displayMode: .all, selected: [],
            attentionMode: .enabled, attentionSelected: [disconnected])
        XCTAssertEqual(remembered.selected, [disconnected, monitor.persistentID, mac.persistentID])

        let followOff = DisplaySelection.togglingAttention(
            monitor, enabled: false, displays: screens, displayMode: .main, selected: [],
            attentionMode: .followDisplay, attentionSelected: [])
        XCTAssertEqual(followOff.mode, .selected)
        XCTAssertTrue(followOff.selected.isEmpty)

        let selectedOn = DisplaySelection.togglingAttention(
            ipad, enabled: true, displays: screens, displayMode: .all, selected: [],
            attentionMode: .selected, attentionSelected: [monitor.persistentID])
        XCTAssertEqual(selectedOn.mode, .selected)
        XCTAssertEqual(selectedOn.selected, [monitor.persistentID, ipad.persistentID])
    }

    func testAttentionIsNeverAddedToADisplayWhoseNotchIsOff() {
        let screens = [monitor, mac, ipad]
        let off = DisplaySelection.togglingAttention(
            ipad, enabled: true, displays: screens, displayMode: .selected,
            selected: [monitor.persistentID], attentionMode: .selected,
            attentionSelected: [])
        XCTAssertEqual(off.mode, .selected)
        XCTAssertTrue(off.selected.isEmpty)

        let follows = DisplaySelection.togglingAttention(
            ipad, enabled: true, displays: screens, displayMode: .selected,
            selected: [monitor.persistentID], attentionMode: .enabled,
            attentionSelected: [])
        XCTAssertEqual(follows.mode, .enabled)
        XCTAssertTrue(follows.selected.isEmpty)
    }

    func testSettingsSidebarPutsDisplaysBetweenGeneralAndStyle() {
        let sidebar = SettingsView.Section.sidebar
        guard let general = sidebar.firstIndex(of: .general),
              let displays = sidebar.firstIndex(of: .displays),
              let style = sidebar.firstIndex(of: .style) else {
            return XCTFail("General, Displays and Style must all be in the sidebar")
        }
        XCTAssertEqual(displays, general + 1)
        XCTAssertEqual(style, displays + 1)
        XCTAssertEqual(SettingsView.Section.displays.title, "Displays")
        XCTAssertEqual(SettingsView.Section.displays.symbol, "display")
        XCTAssertFalse(sidebar.contains(.setup))
    }

    func testDisplayModeKeepsRawSelectedValueWithCustomTitle() {
        XCTAssertEqual(Preferences.DisplayMode.selected.rawValue, "selected")
        XCTAssertEqual(Preferences.DisplayMode.selected.title, "Custom")
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

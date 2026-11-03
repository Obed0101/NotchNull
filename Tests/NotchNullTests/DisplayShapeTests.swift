import XCTest
@testable import NotchNull

@MainActor
final class DisplayShapeTests: XCTestCase {
    private let notched = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchSize: CGSize(width: 185, height: 32), hasHardwareNotch: true)
    private let flat = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1800, height: 1125), notchSize: CGSize(width: 190, height: 30), hasHardwareNotch: false)

    private var savedShape: Preferences.ShapeStyle = .auto
    private var savedShapes: [String: Preferences.DisplayShape] = [:]
    private var savedExtra: Double = 0
    private var savedSatellites = true
    private var savedScale: Double = 1
    private var savedIslandWidth: Double = 0
    private var savedIslandHeight: Double = 0
    private var savedIslandTop: Double = 2
    private var savedPillContent: Preferences.PillContent = .clock

    override func setUp() async throws {
        let preferences = Preferences.shared
        savedShape = preferences.shapeStyle
        savedShapes = preferences.displayShapes
        savedExtra = preferences.closedExtraWidth
        savedSatellites = preferences.islandSatellites
        savedScale = preferences.activityWidthScale
        savedIslandWidth = preferences.islandWidth
        savedIslandHeight = preferences.islandHeight
        savedIslandTop = preferences.islandTop
        savedPillContent = preferences.pillContent
        preferences.shapeStyle = .auto
        preferences.displayShapes = [:]
        preferences.closedExtraWidth = 0
        // The music-to-satellite test depends on satellites, and the OSD width tests depend on a
        // known island size, so neither reads whatever the developer or another test left behind.
        preferences.islandSatellites = true
        preferences.activityWidthScale = 1
        preferences.islandWidth = 0
        preferences.islandHeight = 0
        preferences.islandTop = 2
        preferences.pillContent = .clock
    }

    override func tearDown() async throws {
        let preferences = Preferences.shared
        preferences.shapeStyle = savedShape
        preferences.displayShapes = savedShapes
        preferences.closedExtraWidth = savedExtra
        preferences.islandSatellites = savedSatellites
        preferences.activityWidthScale = savedScale
        preferences.islandWidth = savedIslandWidth
        preferences.islandHeight = savedIslandHeight
        preferences.islandTop = savedIslandTop
        preferences.pillContent = savedPillContent
    }

    /// The activity sink is `receive(on: RunLoop.main)`, so a change lands on a later run-loop
    /// turn. Poll for it instead of sleeping a fixed time, and fail with what was expected.
    @discardableResult
    private func waitFor(
        _ expectation: NotchViewModel.Phase,
        in display: NotchViewModel,
        timeout: TimeInterval = 2,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while display.phase != expectation {
            guard Date() < deadline else {
                XCTFail("Expected \(expectation), still \(display.phase) after \(timeout)s", file: file, line: line)
                return false
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        return true
    }

    private func model(_ geometry: NotchGeometry, displayID: String = "") -> NotchViewModel {
        NotchViewModel(geometry: geometry, displayID: displayID, center: ActivityCenter())
    }

    func testStoredOverridesStartEmptyAndResetClearsThem() {
        XCTAssertEqual(Preferences.decodeDisplayShapes(nil), [:])
        XCTAssertEqual(Preferences.decodeDisplayShapes(Data("not json".utf8)), [:])
        XCTAssertTrue(Preferences.customizationKeys.contains(Preferences.Keys.displayShapes))
    }

    func testStoredOverridesRoundTripByDisplayIdentity() {
        let id = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
        let data = try? JSONEncoder().encode([id: Preferences.DisplayShape(style: .island, housingGap: false)])
        let decoded = Preferences.decodeDisplayShapes(data)
        XCTAssertEqual(decoded[id]?.style, .island)
        XCTAssertEqual(decoded[id]?.housingGap, false)
    }

    func testGlobalDefaultAppliesWhenADisplayHasNoOverride() {
        let notch = DisplayShapeResolver.resolve(default: .notch, override: nil, hasHardwareNotch: false)
        XCTAssertFalse(notch.island)
        XCTAssertTrue(notch.housingGap)
        XCTAssertFalse(notch.spansMiddle)

        XCTAssertFalse(DisplayShapeResolver.resolve(default: .auto, override: nil, hasHardwareNotch: true).island)
        let autoFlat = DisplayShapeResolver.resolve(default: .auto, override: nil, hasHardwareNotch: false)
        XCTAssertTrue(autoFlat.island)
        XCTAssertTrue(autoFlat.spansMiddle)
    }

    func testAnOverrideWinsOverTheGlobalDefault() {
        let island = DisplayShapeResolver.resolve(default: .notch, override: .init(style: .island), hasHardwareNotch: true)
        XCTAssertTrue(island.island)
        XCTAssertTrue(island.spansMiddle)

        let notch = DisplayShapeResolver.resolve(default: .island, override: .init(style: .notch), hasHardwareNotch: false)
        XCTAssertFalse(notch.island)
        XCTAssertFalse(notch.spansMiddle)
    }

    func testOmittingTheHousingSpansTheMiddleWithoutBecomingAnIsland() {
        let presentation = DisplayShapeResolver.resolve(default: .auto, override: .init(style: .notch, housingGap: false), hasHardwareNotch: false)
        XCTAssertFalse(presentation.island)
        XCTAssertFalse(presentation.housingGap)
        XCTAssertTrue(presentation.spansMiddle)
    }

    func testAHardwareNotchAlwaysAssumesTheHousing() {
        let presentation = DisplayShapeResolver.resolve(default: .notch, override: .init(style: .notch, housingGap: false), hasHardwareNotch: true)
        XCTAssertTrue(presentation.housingGap)
        XCTAssertFalse(presentation.spansMiddle)
    }

    func testModelResolvesItsOwnDisplayIncludingAfterARebuild() {
        Preferences.shared.displayShapes = ["FLAT-1": .init(style: .island)]

        let first = model(flat, displayID: "FLAT-1")
        XCTAssertTrue(first.isIsland)
        // The coordinator rebuilds the model when the geometry changes; the identity does not.
        let rebuilt = model(flat, displayID: "FLAT-1")
        XCTAssertEqual(rebuilt.presentation, first.presentation)
        // Another screen, or one built for a snapshot, follows the global default.
        XCTAssertFalse(model(notched, displayID: "OTHER").isIsland)
        XCTAssertTrue(model(flat).isIsland)
    }

    func testOmittingTheHousingKeepsTheClosedPillAndOpensTheMiddle() {
        Preferences.shared.displayShapes = ["FLAT": .init(style: .notch, housingGap: false)]
        let display = model(flat, displayID: "FLAT")
        XCTAssertFalse(display.isIsland)
        XCTAssertTrue(display.spansMiddle)
        // The idle body, its width and its hover target are unchanged.
        XCTAssertEqual(display.closedSize, CGSize(width: 190, height: 30))
        // The middle stops being reserved.
        XCTAssertEqual(display.wingGap, Theme.Size.islandWingGap)
        XCTAssertEqual(display.headerGap, 8)

        display.preview(phase: .activity(.volume))
        XCTAssertEqual(display.bodySize.width, 422)
        display.preview(phase: .activity(.music))
        XCTAssertEqual(display.bodySize.width, 274)
        // The footprint matches the assumed-housing notch exactly; only the layout inside changes.
        XCTAssertEqual(display.headerGap, 8)
        // The silhouette is still the notch, not the island.
        XCTAssertEqual(display.bodyTop, 0)
        XCTAssertEqual(display.topRadius, Theme.Radius.closedTop)
        XCTAssertEqual(display.capRadius, 0)
        XCTAssertNil(display.satelliteFrames)
    }

    func testAssumedHousingKeepsTheNotchMiddle() {
        Preferences.shared.displayShapes = ["FLAT": .init(style: .notch)]
        let display = model(flat, displayID: "FLAT")
        XCTAssertFalse(display.spansMiddle)
        XCTAssertEqual(display.wingGap, 190)
        XCTAssertEqual(display.headerGap, 198)
        display.preview(phase: .activity(.volume))
        // Unmeasured wings fall back to the layout's 116 pt each side.
        XCTAssertEqual(display.bodySize.width, 422)
        display.preview(phase: .activity(.music))
        XCTAssertEqual(display.bodySize.width, 274)
    }

    func testSettingsFileAppliesValidOverridesAndRejectsOnlyBadEntries() {
        let good = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
        let other = "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
        let valid = Data(#"{"look":{"displays":{"\#(good.lowercased())":{"shape":"island","housingGap":false}}}}"#.utf8)
        XCTAssertEqual(SettingsFile.shared.apply(valid, isPatch: true), [])
        XCTAssertEqual(Preferences.shared.displayShapes[good], Preferences.DisplayShape(style: .island, housingGap: false))

        let mixed = Data(#"{"look":{"displays":{"\#(good)":{"shape":"notch","housingGap":false},"not-a-uuid":{"shape":"island"},"\#(other)":{"shape":"round"}}}}"#.utf8)
        let problems = SettingsFile.shared.apply(mixed, isPatch: true)
        XCTAssertEqual(problems.count, 1)
        XCTAssertTrue(problems[0].contains("not-a-uuid"))
        XCTAssertTrue(problems[0].contains("shape: use"))
        XCTAssertEqual(Preferences.shared.displayShapes[good], Preferences.DisplayShape(style: .notch, housingGap: false))
        XCTAssertNil(Preferences.shared.displayShapes[other])

        // A connected or not, any syntactically valid UUID is kept for when the screen returns.
        let unknown = "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"
        XCTAssertEqual(SettingsFile.shared.apply(Data(#"{"look":{"displays":{"\#(unknown)":{"shape":"island"}}}}"#.utf8), isPatch: true), [])
        XCTAssertEqual(Preferences.shared.displayShapes[unknown], Preferences.DisplayShape(style: .island))
    }

    func testARejectedEntryKeepsTheOverrideItAlreadyHad() {
        let id = "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD"
        let stored = Preferences.DisplayShape(style: .island, housingGap: false)
        Preferences.shared.displayShapes = [id: stored]
        let before = DisplayShapeResolver.resolve(default: .auto, override: Preferences.shared.displayShapes[id], hasHardwareNotch: false)

        // A typo in the shape is reported, and the screen keeps presenting exactly as it did.
        let problems = SettingsFile.shared.apply(Data(#"{"look":{"displays":{"\#(id)":{"shape":"round"}}}}"#.utf8), isPatch: true)
        XCTAssertEqual(problems.count, 1)
        XCTAssertTrue(problems.first?.contains("shape: use") == true)
        XCTAssertEqual(Preferences.shared.displayShapes[id], stored)
        XCTAssertEqual(DisplayShapeResolver.resolve(default: .auto, override: Preferences.shared.displayShapes[id], hasHardwareNotch: false), before)

        // The same holds for a housing flag that is not a boolean at all. (A string is coerced, so
        // "no" would be accepted as false; an object is what actually fails.)
        let badFlag = SettingsFile.shared.apply(Data(#"{"look":{"displays":{"\#(id)":{"shape":"notch","housingGap":{}}}}}"#.utf8), isPatch: true)
        XCTAssertEqual(badFlag.count, 1)
        XCTAssertTrue(badFlag.first?.contains("housingGap") == true)
        XCTAssertEqual(Preferences.shared.displayShapes[id], stored)

        // The rewrite that follows cannot erase it either, since the snapshot reads the kept value.
        XCTAssertEqual(SettingsFile.shared.snapshot().value(at: "look.displays.\(id).shape")?.string, "island")
        XCTAssertEqual(SettingsFile.shared.snapshot().value(at: "look.displays.\(id).housingGap")?.bool, false)
    }

    func testAcceptedEntriesApplyNextToOneThatIsRejectedAndOmissionStillForgets() {
        let kept = "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE"
        let accepted = "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"
        Preferences.shared.displayShapes = [kept: Preferences.DisplayShape(style: .island)]

        let problems = SettingsFile.shared.apply(Data(#"{"look":{"displays":{"\#(kept)":{"shape":"nope"},"\#(accepted)":{"shape":"notch"}}}}"#.utf8), isPatch: true)
        XCTAssertEqual(problems.count, 1)
        XCTAssertEqual(Preferences.shared.displayShapes[kept], Preferences.DisplayShape(style: .island))
        XCTAssertEqual(Preferences.shared.displayShapes[accepted], Preferences.DisplayShape(style: .notch))

        // Removing an entry from the object still forgets that screen: only a rejected entry is kept.
        XCTAssertEqual(SettingsFile.shared.apply(Data(#"{"look":{"displays":{"\#(accepted)":{"shape":"notch"}}}}"#.utf8), isPatch: true), [])
        XCTAssertNil(Preferences.shared.displayShapes[kept])
        XCTAssertEqual(Preferences.shared.displayShapes[accepted], Preferences.DisplayShape(style: .notch))
    }

    func testAnOverrideForAShownScreenNeedsNoOrphanRow() {
        let shown = display("SHOWN", name: "Built-in")
        let others = [shown, display("SIDE", name: "Sidecar")]
        // SHOWN has a row of its own, so only SIDE's override needs the extra list.
        let orphans = DisplayShapeResolver.orphanOverrides(stored: ["SHOWN"], connected: others, eligible: ["SHOWN"])
        XCTAssertEqual(orphans, [])
    }

    func testAnOverrideForAConnectedButUnshownScreenIsListedAndNamed() {
        let hidden = display("HIDDEN", name: "Studio Display")
        let orphans = DisplayShapeResolver.orphanOverrides(stored: ["HIDDEN"], connected: [hidden], eligible: [])
        XCTAssertEqual(orphans.count, 1)
        // Named, flagged as connected, and explained: not called a disconnected display.
        XCTAssertEqual(orphans[0].id, "HIDDEN")
        XCTAssertEqual(orphans[0].title, "Studio Display")
        XCTAssertTrue(orphans[0].isConnected)
        XCTAssertTrue(orphans[0].subtitle.contains("HIDDEN"))
        XCTAssertNotEqual(orphans[0].title, "Disconnected display")
    }

    func testAnOverrideForAnAbsentScreenStaysListedAsDisconnected() {
        let orphans = DisplayShapeResolver.orphanOverrides(stored: ["GONE"], connected: [display("HERE", name: "Built-in")], eligible: ["HERE"])
        XCTAssertEqual(orphans.count, 1)
        XCTAssertEqual(orphans[0].title, "Disconnected display")
        XCTAssertFalse(orphans[0].isConnected)
        XCTAssertEqual(orphans[0].subtitle, "GONE")
    }

    func testAnOverrideIsNeverDroppedFromBothLists() {
        // The bug: no display is eligible, so there are no screen rows, and filtering the stored keys
        // against every connected screen would drop this one too. It must still be reachable.
        let stored: Set<String> = ["ONLY"]
        let connected = [display("ONLY", name: "Built-in")]
        let orphans = DisplayShapeResolver.orphanOverrides(stored: stored, connected: connected, eligible: [])
        XCTAssertEqual(orphans.map(\.id), ["ONLY"])
        // Every stored override lands in exactly one place: this list, or a screen row.
        for id in stored {
            let inRows = !Set(orphans.map(\.id)).contains(id)
            XCTAssertTrue(inRows || orphans.contains { $0.id == id })
        }
        // Sorted, so rows do not move between launches.
        XCTAssertEqual(DisplayShapeResolver.orphanOverrides(stored: ["B", "A", "C"], connected: [], eligible: []).map(\.id), ["A", "B", "C"])
    }

    /// NotchDisplay needs real screens to build itself, but the members are plain values.
    private func display(_ id: String, name: String) -> NotchDisplay {
        NotchDisplay(id: 1, persistentID: id, name: name, frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                     builtIn: false, hasNotch: false, scale: 1)
    }

    func testTheDocumentedSettingsExampleApplies() {
        let example = Data(#"{"look":{"shape":"auto","displays":{"37D8832A-2D66-02CA-B9F7-8F30A301B230":{"shape":"notch","housingGap":false}}}}"#.utf8)
        XCTAssertEqual(SettingsFile.shared.apply(example, isPatch: true), [])
        XCTAssertEqual(Preferences.shared.displayShapes["37D8832A-2D66-02CA-B9F7-8F30A301B230"],
                       Preferences.DisplayShape(style: .notch, housingGap: false))
    }

    func testTheSettingsReferenceDocumentsPerDisplayShape() {
        XCTAssertTrue(SettingsFile.reference.contains("look.displays"))
        XCTAssertTrue(SettingsFile.reference.contains("look.shape"))
    }

    func testScreenSubtitleNamesTheStoredChoiceOnce() {
        func subtitle(_ stored: Preferences.ShapeStyle?, notch: Bool = false, housing: Bool = true, global: Preferences.ShapeStyle = .auto) -> String {
            DisplayShapeResolver.subtitle(
                size: "1680 × 1050 pt",
                stored: stored,
                presentation: DisplayShapeResolver.resolve(
                    default: global,
                    override: stored.map { Preferences.DisplayShape(style: $0, housingGap: housing) },
                    hasHardwareNotch: notch
                ),
                hasHardwareNotch: notch
            )
        }
        // A stored choice is named once, and a body only when the choice does not name one.
        XCTAssertEqual(subtitle(nil), "1680 × 1050 pt · Default · Island")
        XCTAssertEqual(subtitle(.auto), "1680 × 1050 pt · Automatic · Island")
        XCTAssertEqual(subtitle(.island), "1680 × 1050 pt · Island")
        XCTAssertEqual(subtitle(.notch), "1680 × 1050 pt · Notch")
        XCTAssertEqual(subtitle(.notch, notch: true), "1680 × 1050 pt · Notch")
        XCTAssertEqual(subtitle(.auto, notch: true), "1680 × 1050 pt · Automatic · Notch")
        // The housing note rides along with the notch body, and only when it can be turned off.
        XCTAssertEqual(subtitle(.notch, notch: false, housing: false), "1680 × 1050 pt · Notch · no camera housing")
        // Default stores no entry, so it cannot carry a housing choice: it always assumes one.
        XCTAssertEqual(subtitle(nil, notch: false, housing: false), "1680 × 1050 pt · Default · Island")
        XCTAssertEqual(subtitle(.notch, notch: true, housing: false), "1680 × 1050 pt · Notch")
        // A stored choice beats the global picker, so the global one is never echoed.
        XCTAssertEqual(subtitle(.island, notch: true, global: .notch), "1680 × 1050 pt · Island")
    }

    func testAPerDisplayAutoOverrideRoundTripsAndStaysSelectable() {
        let id = "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD"
        XCTAssertEqual(SettingsFile.shared.apply(Data(#"{"look":{"displays":{"\#(id)":{"shape":"auto"}}}}"#.utf8), isPatch: true), [])
        XCTAssertEqual(Preferences.shared.displayShapes[id], Preferences.DisplayShape(style: .auto))
        // Every accepted value must have a tag in the per-screen picker, or a stored override shows
        // as a blank control. Automatic is a real stored value, so it is part of the option set.
        let options: [Preferences.ShapeStyle?] = [nil] + Preferences.ShapeStyle.allCases.map { Optional($0) }
        XCTAssertTrue(options.contains(Preferences.shared.displayShapes[id]?.style))
        // It resolves through that screen's hardware, not through the global picker.
        let resolved = DisplayShapeResolver.resolve(
            default: .notch,
            override: Preferences.shared.displayShapes[id],
            hasHardwareNotch: false
        )
        XCTAssertTrue(resolved.island)
    }

    func testSwitchingToIslandMovesPlayingMusicIntoItsSatellite() {
        let center = ActivityCenter()
        let preferences = Preferences.shared
        preferences.displayShapes = ["FLAT": .init(style: .notch)]
        let display = NotchViewModel(geometry: flat, displayID: "FLAT", center: center)
        center.setPersistent(.music, active: true)
        waitFor(.activity(.music), in: display)

        // The change must take effect without a new activity event or a relaunch.
        preferences.displayShapes = ["FLAT": .init(style: .island)]
        waitFor(.closed, in: display)

        preferences.displayShapes = ["FLAT": .init(style: .notch)]
        waitFor(.activity(.music), in: display)
    }

    func testTheIslandOSDKeepsTheHUDWidthInsteadOfFillingTheBody() {
        let island = model(flat)
        XCTAssertTrue(island.isIsland)
        XCTAssertEqual(island.osdRowWidth, NotchViewModel.osdWidthBase)

        Preferences.shared.activityWidthScale = 1.4
        XCTAssertEqual(island.osdRowWidth ?? -1, 274.4, accuracy: 0.01)
    }

    func testANotchOSDFillsTheBodyWhetherOrNotItAssumesTheHousing() {
        Preferences.shared.displayShapes = ["FLAT": .init(style: .notch)]
        let housing = model(flat, displayID: "FLAT")
        XCTAssertFalse(housing.spansMiddle)
        XCTAssertNil(housing.osdRowWidth)

        Preferences.shared.displayShapes = ["FLAT": .init(style: .notch, housingGap: false)]
        let spanning = model(flat, displayID: "FLAT")
        XCTAssertTrue(spanning.spansMiddle)
        XCTAssertNil(spanning.osdRowWidth)
    }

    func testThePinnedIslandOSDRowNeverOutgrowsTheBody() {
        let island = model(flat)
        island.preview(phase: .activity(.volume))
        let row = island.osdRowWidth ?? 0
        XCTAssertGreaterThan(row, 0)
        XCTAssertLessThanOrEqual(row, island.bodySize.width)

        // The pin follows the scale the body already uses, so it grows with it.
        Preferences.shared.activityWidthScale = Preferences.Limits.activityWidthScale.upperBound
        XCTAssertEqual(island.osdRowWidth, NotchViewModel.osdWidth(scale: Preferences.Limits.activityWidthScale.upperBound))
    }

    func testAStoredPreferenceCannotOpenAHardwareNotch() {
        Preferences.shared.displayShapes = ["NOTCHED": .init(style: .notch, housingGap: false)]
        let display = model(notched, displayID: "NOTCHED")
        XCTAssertFalse(display.spansMiddle)
        XCTAssertEqual(display.wingGap, 185)
        XCTAssertEqual(display.headerGap, 193)
    }
}

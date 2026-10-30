import XCTest
@testable import NotchNull

@MainActor
final class DisplayShapeTests: XCTestCase {
    private let notched = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchSize: CGSize(width: 185, height: 32), hasHardwareNotch: true)
    private let flat = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1800, height: 1125), notchSize: CGSize(width: 190, height: 30), hasHardwareNotch: false)

    private var savedShape: Preferences.ShapeStyle = .auto
    private var savedShapes: [String: Preferences.DisplayShape] = [:]
    private var savedExtra: Double = 0

    override func setUp() async throws {
        let preferences = Preferences.shared
        savedShape = preferences.shapeStyle
        savedShapes = preferences.displayShapes
        savedExtra = preferences.closedExtraWidth
        preferences.shapeStyle = .auto
        preferences.displayShapes = [:]
        preferences.closedExtraWidth = 0
    }

    override func tearDown() async throws {
        let preferences = Preferences.shared
        preferences.shapeStyle = savedShape
        preferences.displayShapes = savedShapes
        preferences.closedExtraWidth = savedExtra
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

    func testSwitchingToIslandMovesPlayingMusicIntoItsSatellite() {
        let center = ActivityCenter()
        let preferences = Preferences.shared
        preferences.displayShapes = ["FLAT": .init(style: .notch)]
        let display = NotchViewModel(geometry: flat, displayID: "FLAT", center: center)
        center.setPersistent(.music, active: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(display.phase, .activity(.music))

        // The change must take effect without a new activity event or a relaunch.
        preferences.displayShapes = ["FLAT": .init(style: .island)]
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(display.phase, .closed)

        preferences.displayShapes = ["FLAT": .init(style: .notch)]
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(display.phase, .activity(.music))
    }

    func testAStoredPreferenceCannotOpenAHardwareNotch() {
        Preferences.shared.displayShapes = ["NOTCHED": .init(style: .notch, housingGap: false)]
        let display = model(notched, displayID: "NOTCHED")
        XCTAssertFalse(display.spansMiddle)
        XCTAssertEqual(display.wingGap, 185)
        XCTAssertEqual(display.headerGap, 193)
    }
}

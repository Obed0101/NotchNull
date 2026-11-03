import XCTest
@testable import NotchNull

@MainActor
final class IslandTests: XCTestCase {
    private let notched = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchSize: CGSize(width: 185, height: 32), hasHardwareNotch: true)
    /// A MacBook at a resolution that leaves the notch area out: the menu bar is 30 pt.
    private let flat = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1800, height: 1125), notchSize: CGSize(width: 190, height: 30), hasHardwareNotch: false)

    private var saved: [String: Any] = [:]

    override func setUp() async throws {
        let preferences = Preferences.shared
        saved = [
            "shape": preferences.shapeStyle, "height": preferences.islandHeight, "width": preferences.islandWidth,
            "top": preferences.islandTop, "satellites": preferences.islandSatellites, "content": preferences.pillContent,
            "panelWidth": preferences.panelWidth, "panelHeight": preferences.panelHeight,
            "shapes": preferences.displayShapes,
        ]
        preferences.shapeStyle = .auto
        preferences.displayShapes = [:]
        preferences.islandHeight = 0
        preferences.islandWidth = 0
        preferences.islandTop = 2
        preferences.islandSatellites = true
        preferences.pillContent = .clock
    }

    override func tearDown() async throws {
        let preferences = Preferences.shared
        preferences.shapeStyle = saved["shape"] as? Preferences.ShapeStyle ?? .auto
        preferences.islandHeight = saved["height"] as? Double ?? 0
        preferences.islandWidth = saved["width"] as? Double ?? 0
        preferences.islandTop = saved["top"] as? Double ?? 2
        preferences.islandSatellites = saved["satellites"] as? Bool ?? true
        preferences.pillContent = saved["content"] as? Preferences.PillContent ?? .clock
        preferences.panelWidth = saved["panelWidth"] as? Double ?? 500
        preferences.panelHeight = saved["panelHeight"] as? Double ?? 148
        preferences.displayShapes = saved["shapes"] as? [String: Preferences.DisplayShape] ?? [:]
    }

    private func model(_ geometry: NotchGeometry, phase: NotchViewModel.Phase = .closed) -> NotchViewModel {
        let model = NotchViewModel(geometry: geometry, center: ActivityCenter())
        model.preview(phase: phase)
        return model
    }

    func testAutomaticFloatsAnIslandOnlyWhenTheScreenShowsNoNotch() {
        XCTAssertFalse(model(notched).isIsland)
        XCTAssertTrue(model(flat).isIsland)
        Preferences.shared.shapeStyle = .island
        XCTAssertTrue(model(notched).isIsland)
        Preferences.shared.shapeStyle = .notch
        XCTAssertFalse(model(flat).isIsland)
    }

    func testIdleIslandSitsInsideTheMenuBarAsAFullPill() {
        let island = model(flat)
        XCTAssertEqual(island.rowHeight, 26)
        XCTAssertEqual(island.bodyTop, 2)
        XCTAssertEqual(island.closedSize.height, 26)
        XCTAssertEqual(island.capRadius, 13)
        XCTAssertEqual(island.bottomRadius, 13)
        XCTAssertEqual(island.topRadius, 0)
        XCTAssertLessThanOrEqual(island.bodyTop + island.rowHeight, flat.notchSize.height)
    }

    func testForcedIslandOnANotchedScreenFloatsBelowTheCameraHousing() {
        Preferences.shared.shapeStyle = .island
        let island = model(notched)
        XCTAssertEqual(island.bodyTop, 32 + 2)
    }

    func testTypedIslandSizeWinsOverTheFit() {
        Preferences.shared.islandWidth = 300
        Preferences.shared.islandHeight = 40
        let island = model(flat)
        XCTAssertEqual(island.closedSize, CGSize(width: 300, height: 40))
    }

    func testSatellitesFlankTheIdlePillAndLeaveWhenItGrows() throws {
        let closed = model(flat)
        let frames = try XCTUnwrap(closed.satelliteFrames)
        let midX = Theme.Size.canvas.width / 2
        XCTAssertEqual(frames.left.maxX, midX - closed.closedSize.width / 2 - Theme.Size.satelliteGap, accuracy: 0.01)
        XCTAssertEqual(frames.right.minX, midX + closed.closedSize.width / 2 + Theme.Size.satelliteGap, accuracy: 0.01)
        // They stay beside the open panel and tall cards, so the pointer can still reach them.
        let open = model(flat, phase: .open)
        let openFrames = try XCTUnwrap(open.satelliteFrames)
        XCTAssertEqual(openFrames.left.maxX, midX - open.bodySize.width / 2 - Theme.Size.satelliteGap, accuracy: 0.01)
        XCTAssertNotNil(model(flat, phase: .activity(.needsYou)).satelliteFrames)
        XCTAssertNil(model(flat, phase: .drop).satelliteFrames)
        // A one-row wing keeps them, pushed out to its edges.
        let wing = model(flat, phase: .activity(.timer))
        let wingFrames = try XCTUnwrap(wing.satelliteFrames)
        XCTAssertEqual(wingFrames.right.minX, midX + wing.bodySize.width / 2 + Theme.Size.satelliteGap, accuracy: 0.01)
        XCTAssertNil(model(notched).satelliteFrames)
        Preferences.shared.islandSatellites = false
        XCTAssertNil(model(flat).satelliteFrames)
    }

    func testTheBodyNeverOutgrowsTheWindowItDrawsIn() {
        Preferences.shared.panelWidth = Preferences.Limits.panelWidth.upperBound
        Preferences.shared.panelHeight = Preferences.Limits.panelHeight.upperBound
        for geometry in [notched, flat] {
            let open = model(geometry, phase: .open)
            XCTAssertLessThanOrEqual(open.shapeSize.width, Theme.Size.canvas.width)
            XCTAssertLessThanOrEqual(open.bodyTop + open.shapeSize.height, Theme.Size.canvas.height)
        }
    }

    func testTheNotchPanelIsNeverNarrowerThanTheCameraHousing() {
        Preferences.shared.panelWidth = 0
        XCTAssertGreaterThanOrEqual(model(notched, phase: .open).bodySize.width, 185)
        XCTAssertEqual(model(flat, phase: .open).bodySize.width, 0)
    }

    func testMusicStaysInItsSatelliteInsteadOfAlsoFillingThePill() {
        let center = ActivityCenter()
        let island = NotchViewModel(geometry: flat, center: center)
        let notch = NotchViewModel(geometry: notched, center: center)
        center.setPersistent(.music, active: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(island.phase, .closed)
        XCTAssertEqual(notch.phase, .activity(.music))
    }

    func testClockFollowsTheTwentyFourHourSwitch() {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: .current, year: 2026, month: 9, day: 29, hour: 17, minute: 5))!
        XCTAssertEqual(IslandClock.string(date, use24Hour: true), "17:05")
        XCTAssertEqual(IslandClock.string(date, use24Hour: false), "5:05")
    }
}

import XCTest
@testable import NotchNull

@MainActor
final class HomeRowsTests: XCTestCase {
    private var saved: ([String], Set<String>) = ([], [])

    override func setUp() async throws {
        saved = (Preferences.shared.homeRows, Preferences.shared.hiddenHomeWidgets)
        Preferences.shared.homeRows = ["keepAwake", "timer"]
        Preferences.shared.hiddenHomeWidgets = []
    }

    override func tearDown() async throws {
        (Preferences.shared.homeRows, Preferences.shared.hiddenHomeWidgets) = saved
    }

    private func widget(_ id: String, _ json: String, data: String = "null") throws -> LoadedWidget {
        let file = URL(fileURLWithPath: "/tmp/widgets/\(id).json")
        let definition = try WidgetDefinition(file: file, json: XCTUnwrap(JSONValue.parse(Data(json.utf8))))
        return LoadedWidget(id: id, file: file, definition: definition, state: .ready(WidgetStore.data(from: data), Date()))
    }

    func testAWidgetRowNotPlacedYetIsAddedAfterTheListedRows() {
        XCTAssertEqual(Preferences.shared.homeKeys(widgetRows: ["ci"]), ["keepAwake", "timer", "widget:ci"])
    }

    func testListedWidgetRowKeepsItsPlaceAndUnknownOrRepeatedNamesAreDropped() {
        Preferences.shared.homeRows = ["widget:ci", "keepAwake", "gone", "widget:deleted", "keepAwake"]
        XCTAssertEqual(Preferences.shared.homeKeys(widgetRows: ["ci"]), ["widget:ci", "keepAwake"])
    }

    func testHidingAWidgetRowKeepsItOutUntilItIsSwitchedOnAgain() {
        Preferences.shared.setHomeKey("widget:ci", visible: false, widgetRows: ["ci"])
        XCTAssertEqual(Preferences.shared.homeKeys(widgetRows: ["ci"]), ["keepAwake", "timer"])
        Preferences.shared.setHomeKey("widget:ci", visible: true, widgetRows: ["ci"])
        XCTAssertEqual(Preferences.shared.homeKeys(widgetRows: ["ci"]), ["keepAwake", "timer", "widget:ci"])
    }

    func testSwitchingABuiltInRowOnAppendsItAndOffRemovesIt() {
        Preferences.shared.setHomeKey("storage", visible: true, widgetRows: [])
        XCTAssertEqual(Preferences.shared.homeRows, ["keepAwake", "timer", "storage"])
        Preferences.shared.setHomeKey("keepAwake", visible: false, widgetRows: [])
        XCTAssertEqual(Preferences.shared.homeRows, ["timer", "storage"])
    }

    func testMovingARowStopsAtBothEnds() {
        Preferences.shared.moveHomeKey("widget:ci", by: -1, widgetRows: ["ci"])
        XCTAssertEqual(Preferences.shared.homeRows, ["keepAwake", "widget:ci", "timer"])
        Preferences.shared.moveHomeKey("widget:ci", by: -5, widgetRows: ["ci"])
        XCTAssertEqual(Preferences.shared.homeRows, ["widget:ci", "keepAwake", "timer"])
        Preferences.shared.moveHomeKey("widget:ci", by: -1, widgetRows: ["ci"])
        XCTAssertEqual(Preferences.shared.homeRows, ["widget:ci", "keepAwake", "timer"])
        Preferences.shared.moveHomeKey("timer", by: 1, widgetRows: ["ci"])
        XCTAssertEqual(Preferences.shared.homeRows, ["widget:ci", "keepAwake", "timer"])
    }

    func testSettingsFileAcceptsWidgetRowsAndReportsUnknownNames() {
        let problems = SettingsFile.shared.apply(Data(#"{"home": {"rows": ["agents", "widget:ci", "nope"]}}"#.utf8), isPatch: true)
        XCTAssertEqual(Preferences.shared.homeRows, ["agents", "widget:ci"])
        XCTAssertEqual(problems, ["home.rows: unknown name nope"])
    }

    func testAWidgetAsksForAHomeRowOnlyWithAHomeBlockAndWhileWhenHolds() throws {
        let plain = try widget("plain", #"{"view": {"type": "text"}}"#)
        XCTAssertNil(plain.homeRow)
        XCTAssertFalse(plain.showsHomeRow)

        let always = try widget("always", #"{"view": {"type": "text"}, "home": {"text": "{{data.n}} open"}}"#, data: #"{"n": 3}"#)
        XCTAssertTrue(always.showsHomeRow)
        XCTAssertEqual(Template.text(always.homeRow?["text"], in: always.scope), "3 open")

        let json = #"{"view": {"type": "text"}, "home": {"text": "x", "when": "{{data.failing | count}}"}}"#
        XCTAssertFalse(try widget("quiet", json, data: #"{"failing": []}"#).showsHomeRow)
        XCTAssertTrue(try widget("loud", json, data: #"{"failing": ["e2e"]}"#).showsHomeRow)
    }

    func testAListAFewPointsTooTallTightensItsRowsBeforeScrolling() {
        XCTAssertEqual(QuickRowsCard.rowHeight(count: 4, available: 120), 26)
        XCTAssertEqual(QuickRowsCard.rowHeight(count: 5, available: 120), 24)
    }
}

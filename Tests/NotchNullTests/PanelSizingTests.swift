import XCTest
@testable import NotchNull

@MainActor
final class PanelSizingTests: XCTestCase {
    private let geometry = NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        notchSize: CGSize(width: 185, height: 32),
        hasHardwareNotch: true
    )

    private var saved: [String: Any] = [:]

    override func setUp() async throws {
        let preferences = Preferences.shared
        saved = [
            "panelWidth": preferences.panelWidth, "panelHeight": preferences.panelHeight,
            "hiddenTabs": preferences.hiddenTabs, "agentsEnabled": preferences.agentsEnabled,
            "shapeStyle": preferences.shapeStyle,
        ]
        preferences.panelWidth = 500
        preferences.panelHeight = 148
        preferences.hiddenTabs = Set(NotchTab.allCases.filter { $0 != .home && $0 != .agents }.map(\.rawValue))
        preferences.agentsEnabled = true
        preferences.shapeStyle = .notch
    }

    override func tearDown() async throws {
        let preferences = Preferences.shared
        preferences.panelWidth = saved["panelWidth"] as? Double ?? 500
        preferences.panelHeight = saved["panelHeight"] as? Double ?? 148
        preferences.hiddenTabs = saved["hiddenTabs"] as? Set<String> ?? []
        preferences.agentsEnabled = saved["agentsEnabled"] as? Bool ?? true
        preferences.shapeStyle = saved["shapeStyle"] as? Preferences.ShapeStyle ?? .auto
    }

    private func openModel(tab: NotchTab) -> NotchViewModel {
        let model = NotchViewModel(geometry: geometry, center: ActivityCenter())
        model.preview(phase: .open, tab: tab)
        return model
    }

    func testOnlyAgentsRequestsExtraHeight() {
        XCTAssertEqual(NotchTab.agents.panelExtraHeight, 16)
        for tab in NotchTab.allCases where tab != .agents {
            XCTAssertEqual(tab.panelExtraHeight, 0, "\(tab) should not grow the panel")
        }
    }

    func testAgentsPanelGrowsPastHomeByItsExtraHeight() {
        let home = openModel(tab: .home)
        let agents = openModel(tab: .agents)
        XCTAssertEqual(home.visibleTab, .home)
        XCTAssertEqual(agents.visibleTab, .agents)
        XCTAssertEqual(home.bodySize.height, home.headerHeight + 148)
        XCTAssertEqual(agents.bodySize.width, home.bodySize.width)
        XCTAssertEqual(agents.bodySize.height - home.bodySize.height, NotchTab.agents.panelExtraHeight)
    }

    func testSwitchingTabsDoesNotLeaveExtraHeightBehind() {
        let model = openModel(tab: .home)
        let homeSize = model.bodySize
        for _ in 0..<3 {
            model.select(.agents)
            XCTAssertEqual(model.bodySize.height, homeSize.height + 16)
            model.select(.home)
            XCTAssertEqual(model.bodySize, homeSize)
        }
        XCTAssertEqual(model.panelContentHeight, 148)
        XCTAssertEqual(Preferences.shared.panelHeight, 148)
    }

    func testHiddenAgentsSelectionUsesTheVisibleTabsHeight() {
        let model = openModel(tab: .agents)
        Preferences.shared.hiddenTabs.insert(NotchTab.agents.rawValue)
        XCTAssertEqual(model.visibleTab, .home)
        XCTAssertEqual(model.bodySize.height, model.headerHeight + 148)
    }

    func testDisabledAgentsSelectionUsesTheVisibleTabsHeight() {
        let model = openModel(tab: .agents)
        Preferences.shared.agentsEnabled = false
        XCTAssertEqual(model.visibleTab, .home)
        XCTAssertEqual(model.bodySize.height, model.headerHeight + 148)
    }

    func testExtraHeightOnlyAppliesToTheOpenPanel() {
        let model = openModel(tab: .home)
        for phase: NotchViewModel.Phase in [.closed, .drop, .activity(.needsYou)] {
            model.preview(phase: phase, tab: .home)
            let homeSize = model.bodySize
            model.preview(phase: phase, tab: .agents)
            XCTAssertEqual(model.bodySize, homeSize)
        }
    }

    func testIslandAgentsPanelAlsoGrowsBySixteenPoints() {
        Preferences.shared.shapeStyle = .island
        let home = openModel(tab: .home)
        let agents = openModel(tab: .agents)
        XCTAssertEqual(agents.bodySize.height - home.bodySize.height, 16)
        XCTAssertEqual(agents.panelContentHeight, 148)
    }

    func testAgentsExtraHeightStillRespectsTheCanvasClamp() {
        let model = openModel(tab: .agents)
        Preferences.shared.panelHeight = Double(Theme.Size.canvas.height)
        XCTAssertEqual(model.bodySize.height, Theme.Size.canvas.height - model.bodyTop - 40)
    }
}

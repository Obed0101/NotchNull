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
        ]
        preferences.panelWidth = 500
        preferences.panelHeight = 148
        preferences.hiddenTabs = []
        preferences.agentsEnabled = true
    }

    override func tearDown() async throws {
        let preferences = Preferences.shared
        preferences.panelWidth = saved["panelWidth"] as? Double ?? 500
        preferences.panelHeight = saved["panelHeight"] as? Double ?? 148
        preferences.hiddenTabs = saved["hiddenTabs"] as? Set<String> ?? []
        preferences.agentsEnabled = saved["agentsEnabled"] as? Bool ?? true
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
        XCTAssertEqual(agents.bodySize.width, home.bodySize.width)
        XCTAssertEqual(agents.bodySize.height - home.bodySize.height, NotchTab.agents.panelExtraHeight)
    }

    func testLiveRequestIsCappedAndFlooredByTheStaticDefault() {
        let model = openModel(tab: .home)
        model.setRequestedPanelExtra(200, for: .home)
        XCTAssertEqual(model.panelExtraHeight(for: .home), NotchTab.maxRequestedPanelExtra)
        // A smaller live request never shrinks below the static default.
        let agents = openModel(tab: .agents)
        agents.setRequestedPanelExtra(0, for: .agents)
        XCTAssertEqual(agents.panelExtraHeight(for: .agents), NotchTab.agents.panelExtraHeight)
        agents.setRequestedPanelExtra(24, for: .agents)
        XCTAssertEqual(agents.panelExtraHeight(for: .agents), 24)
    }
}

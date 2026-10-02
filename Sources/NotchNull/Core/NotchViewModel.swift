import AppKit
import Combine
import SwiftUI

enum NotchTab: String, CaseIterable, Identifiable {
    case home, recent, agents, controls, widgets, tray, downloads, clipboard, mirror

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .recent: "Recent"
        case .widgets: "Widgets"
        case .agents: "Agents"
        case .controls: "Controls"
        case .tray: "Tray"
        case .downloads: "Downloads"
        case .clipboard: "Clipboard"
        case .mirror: "Mirror"
        }
    }

    var symbol: String {
        switch self {
        case .home: "square.grid.2x2.fill"
        case .recent: "clock.fill"
        case .widgets: "rectangle.3.group.fill"
        case .agents: "sparkle"
        case .controls: "switch.2"
        case .tray: "tray.full.fill"
        case .downloads: "arrow.down.circle.fill"
        case .clipboard: "list.clipboard.fill"
        case .mirror: "web.camera.fill"
        }
    }
}

/// Per-screen presentation state: one body morphing out of the hardware notch.
@MainActor
final class NotchViewModel: ObservableObject {
    enum Phase: Equatable {
        case closed
        case activity(ActivityKind)
        case open
        case drop
    }

    let geometry: NotchGeometry

    @Published private(set) var phase: Phase = .closed
    @Published var selectedTab: NotchTab = .home
    @Published var isPointerInside = false
    /// Direction of the last tab change, used for the directional content slide.
    @Published private(set) var tabDirection: Edge = .trailing

    private var isOpen = false
    private var isDropping = false
    private var activity: ActivityKind?
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var cancellables: Set<AnyCancellable> = []
    private let preferences = Preferences.shared

    convenience init(geometry: NotchGeometry) {
        self.init(geometry: geometry, center: ActivityCenter.shared)
    }

    init(geometry: NotchGeometry, center: ActivityCenter) {
        self.geometry = geometry
        center.$current
            .receive(on: RunLoop.main)
            .sink { [weak self] kind in self?.activityChanged(kind) }
            .store(in: &cancellables)
        // Size preferences change the body live, a custom activity sizes itself to its content,
        // and the needs-you banner grows with each waiting session.
        preferences.objectWillChange
            .merge(with: CustomActivityStore.shared.objectWillChange, AttentionQueue.shared.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.objectWillChange.send() } }
            .store(in: &cancellables)
    }

    // MARK: Geometry

    /// The hardware notch (or the virtual one on displays without a notch).
    var notchSize: CGSize { geometry.notchSize }

    /// Island style floats a pill instead of growing out of the notch. Automatic picks it on
    /// screens without a hardware notch, such as a MacBook at a resolution that leaves it out.
    var isIsland: Bool {
        switch preferences.shapeStyle {
        case .auto: !geometry.hasHardwareNotch
        case .notch: false
        case .island: true
        }
    }

    /// Height of the first row in every state: the notch, or the island pill.
    var rowHeight: CGFloat {
        guard isIsland else { return notchSize.height }
        // 0 fits the pill inside the menu bar (the virtual notch is the menu bar's height).
        return preferences.islandHeight > 0 ? CGFloat(preferences.islandHeight) : max(20, notchSize.height - 4)
    }

    /// Distance from the top of the screen to the top of the body. A forced island on a notched
    /// screen floats below the camera housing.
    var bodyTop: CGFloat {
        guard isIsland else { return 0 }
        return (geometry.hasHardwareNotch ? notchSize.height : 0) + CGFloat(preferences.islandTop)
    }

    /// Room kept between the two wings: the camera housing, or a small gap in the island.
    var wingGap: CGFloat { isIsland ? Theme.Size.islandWingGap : closedSize.width }

    /// Room kept in the middle of the panel header, for the same reason.
    var headerGap: CGFloat { isIsland ? 8 : notchSize.width + 8 }

    /// Height of the open panel's header. The notch's header is the notch row; the island's is a
    /// little taller so the tabs clear its rounded top corners.
    var headerHeight: CGFloat { isIsland ? max(rowHeight, 30) + 8 : notchSize.height }

    /// Extra side inset for the header, so the tabs and actions sit inside the island's corners.
    var headerInset: CGFloat { isIsland ? min(14, capRadius * 0.35) : 0 }

    /// An island banner (an activity with a row below) has the panel's large rounded corners, so
    /// its top row gets the header's height and inset; otherwise icons sit in the curve.
    private var isIslandBanner: Bool {
        guard isIsland, case .activity(let kind) = phase else { return false }
        return kind.layout.extraHeight > 0
    }

    /// Height of the first row of the current body: the header when open, the notch or pill row
    /// otherwise, and the header's height for island banners.
    var contentRowHeight: CGFloat { isExpanded || isIslandBanner ? headerHeight : rowHeight }

    /// Side inset of the first row's content.
    var contentRowInset: CGFloat {
        if isIslandBanner { return Theme.Radius.panelPadding + headerInset }
        return isIsland ? max(Self.wingOuterPadding, min(18, capRadius * 0.6)) : Self.wingOuterPadding
    }

    /// The closed body. A notch is the hardware notch plus the user's extra width (it can only
    /// grow: nothing can be drawn over the camera housing); an island fits what it shows.
    var closedSize: CGSize {
        if isIsland {
            let width = preferences.islandWidth > 0 ? CGFloat(preferences.islandWidth) : Self.pillWidth(for: preferences.pillContent, height: rowHeight)
            return CGSize(width: width, height: rowHeight)
        }
        return CGSize(width: notchSize.width + CGFloat(preferences.closedExtraWidth), height: notchSize.height)
    }

    /// Idle island width for what it shows, scaled with its height.
    static func pillWidth(for content: Preferences.PillContent, height: CGFloat) -> CGFloat {
        let base: CGFloat
        switch content {
        case .clock: base = 78
        case .dateClock: base = 132
        case .battery: base = 80
        case .clockBattery: base = 132
        case .nothing: base = 110
        }
        return base * max(0.6, height / 28)
    }

    var panelContentHeight: CGFloat { CGFloat(preferences.panelHeight) }

    /// Live per-tab growth requests from `.panelExtraHeight`, keyed by tab so
    /// switching tabs never flashes the previous tab's height.
    @Published private(set) var requestedPanelExtra: [NotchTab: CGFloat] = [:]

    /// Extra open-panel height for `tab`: the static default as floor, any live
    /// view request on top of it, capped.
    func panelExtraHeight(for tab: NotchTab) -> CGFloat {
        let live = min(max(requestedPanelExtra[tab] ?? 0, 0), NotchTab.maxRequestedPanelExtra)
        return max(tab.panelExtraHeight, live)
    }

    func setRequestedPanelExtra(_ height: CGFloat, for tab: NotchTab) {
        let clamped = min(max(height, 0), NotchTab.maxRequestedPanelExtra)
        guard abs((requestedPanelExtra[tab] ?? 0) - clamped) > 0.01 else { return }
        requestedPanelExtra[tab] = clamped
    }
    /// The notch panel is never narrower than the camera housing it hangs from; an island can be any width.
    var panelWidth: CGFloat { isIsland ? CGFloat(preferences.panelWidth) : max(CGFloat(preferences.panelWidth), closedSize.width + 40) }

    var bodySize: CGSize {
        let size: CGSize
        switch phase {
        case .closed:
            size = closedSize
        case .open:
            size = CGSize(width: panelWidth, height: headerHeight + panelContentHeight + panelExtraHeight(for: visibleTab))
        case .drop:
            size = CGSize(width: max(panelWidth, 360), height: headerHeight + Theme.Size.dropContentHeight)
        case .activity(let kind):
            let layout = kind.layout
            let scale = CGFloat(preferences.activityWidthScale)
            // Wings hug their content: measured width + a small gap to the center + the outer padding.
            let wing = measuredWings[kind].map { $0 + Self.wingInnerGap + Self.wingOuterPadding } ?? layout.wing
            let wingsWidth = wingGap + wing * 2 * scale
            let contentWidth = isIsland ? layout.islandWidth.map { $0 * scale } ?? wingsWidth : wingsWidth
            let width = max(contentWidth, layout.minWidth * scale, isIsland ? closedSize.width : closedSize.width + 40)
            size = CGSize(width: width, height: contentRowHeight + layout.extraHeight)
        }
        // The window the body draws in is the only hard limit.
        let canvas = Theme.Size.canvas
        return CGSize(
            width: min(size.width, canvas.width - topRadius * 2 - 40),
            height: min(size.height, canvas.height - bodyTop - 40)
        )
    }

    static let wingInnerGap: CGFloat = 8
    static let wingOuterPadding: CGFloat = 12

    /// Widest wing content measured per activity, so each wing is only as wide as what it shows.
    @Published private(set) var measuredWings: [ActivityKind: CGFloat] = [:]

    func reportWingContent(_ width: CGFloat, for kind: ActivityKind) {
        let rounded = ceil(width)
        guard rounded > 0, abs((measuredWings[kind] ?? 0) - rounded) > 1 else { return }
        withAnimation(Motion.value) { measuredWings[kind] = rounded }
    }

    /// Concave flare where the notch meets the menu bar. The island has none.
    var topRadius: CGFloat {
        guard !isIsland else { return 0 }
        switch phase {
        case .closed: return Theme.Radius.closedTop
        case .activity(let kind): return kind.layout.extraHeight > 0 ? Theme.Radius.openTop * 0.8 : Theme.Radius.closedTop
        case .open, .drop: return Theme.Radius.openTop
        }
    }

    /// A body only one row tall: the closed notch or island, or a wing without a row below it.
    private var isSingleRow: Bool {
        switch phase {
        case .closed: true
        case .activity(let kind): kind.layout.extraHeight == 0
        case .open, .drop: false
        }
    }

    var bottomRadius: CGFloat {
        let scale = CGFloat(preferences.cornerScale)
        if isIsland && isSingleRow { return rowHeight / 2 * min(1, scale) }
        switch phase {
        case .closed: return Theme.Radius.closedBottom
        case .activity(let kind): return (kind.layout.extraHeight > 0 ? Theme.Radius.openBottom * 0.75 : Theme.Radius.compactBottom) * scale
        case .open, .drop: return Theme.Radius.openBottom * scale
        }
    }

    /// Convex top corners of the island, matching its bottom ones. 0 for the notch.
    var capRadius: CGFloat { isIsland ? bottomRadius : 0 }

    enum SatelliteSide: Equatable { case leading, trailing }

    /// The satellite grown into its card: media on the left, control center on the right.
    @Published private(set) var expandedSatellite: SatelliteSide?
    private var satelliteWork: DispatchWorkItem?
    private var hoveredSatellite: SatelliteSide?

    static let mediaCardSize = CGSize(width: 400, height: 146)
    static let controlsCardSize = CGSize(width: 440, height: 168)

    /// The island's satellites, in canvas coordinates. They stay beside the body in every state
    /// (idle pill, wings, cards and the open panel) so the pointer can always move over to one,
    /// and one of them grows into its own card while hovered.
    var satelliteFrames: (left: CGRect, right: CGRect)? {
        guard isIsland, preferences.islandSatellites, phase != .drop, rowHeight >= 12 else { return nil }
        let size = rowHeight
        let gap = Theme.Size.satelliteGap
        let midX = Theme.Size.canvas.width / 2
        let half = bodySize.width / 2
        let y = bodyTop
        var left = CGRect(x: midX - half - gap - size, y: y, width: size, height: size)
        var right = CGRect(x: midX + half + gap, y: y, width: size, height: size)
        switch expandedSatellite {
        case .leading:
            let card = Self.mediaCardSize
            left = clampedToCanvas(CGRect(x: left.maxX - card.width, y: y, width: card.width, height: card.height))
        case .trailing:
            let card = Self.controlsCardSize
            right = clampedToCanvas(CGRect(x: right.minX, y: y, width: card.width, height: card.height))
        case nil:
            break
        }
        return (left, right)
    }

    /// Radius for a satellite: a circle, or a card's rounded corners.
    func satelliteRadius(for frame: CGRect) -> CGFloat {
        frame.width <= frame.height + 1 ? frame.height / 2 : min(frame.height / 2, 26 * CGFloat(preferences.cornerScale))
    }

    func toggleSatellite(_ side: SatelliteSide) {
        satelliteWork?.cancel()
        if expandedSatellite != side { close() }
        withAnimation(expandedSatellite == side ? Motion.close : Motion.open) {
            expandedSatellite = expandedSatellite == side ? nil : side
        }
    }

    private func clampedToCanvas(_ rect: CGRect) -> CGRect {
        let margin: CGFloat = 16
        var result = rect
        result.origin.x = min(max(margin, rect.minX), Theme.Size.canvas.width - margin - rect.width)
        return result
    }

    /// Hovering a satellite grows it into its card; leaving the card lets it shrink back.
    private func updateSatelliteHover(at point: CGPoint) {
        let rects = satelliteScreenRects
        let over: SatelliteSide? = rects.count == 2
            ? (rects[0].contains(point) ? .leading : rects[1].contains(point) ? .trailing : nil)
            : nil
        guard over != hoveredSatellite else { return }
        hoveredSatellite = over
        if let over {
            guard preferences.openTrigger == .hover, expandedSatellite != over else {
                satelliteWork?.cancel()
                return
            }
            openWork?.cancel()
            schedule(&satelliteWork, after: Motion.hoverOpenDelay + 0.06) { [weak self] in
                guard let self, self.hoveredSatellite == over else { return }
                // One thing out at a time: the panel tucks back in as the card grows.
                self.close()
                withAnimation(Motion.open) { self.expandedSatellite = over }
            }
        } else if expandedSatellite != nil {
            schedule(&satelliteWork, after: Motion.hoverCloseDelay) { [weak self] in
                guard let self, self.hoveredSatellite == nil else { return }
                withAnimation(Motion.close) { self.expandedSatellite = nil }
            }
        } else {
            satelliteWork?.cancel()
        }
    }

    /// Screen-space rects of the satellites, for clicks.
    private var satelliteScreenRects: [CGRect] {
        guard let frames = satelliteFrames else { return [] }
        let offset = (Theme.Size.canvas.width / 2) - geometry.screenFrame.midX
        return [frames.left, frames.right].map {
            CGRect(x: $0.minX - offset, y: geometry.screenFrame.maxY - $0.maxY, width: $0.width, height: $0.height).insetBy(dx: -3, dy: -3)
        }
    }

    /// The shape is drawn wider than the body by the top flare on both sides.
    var shapeSize: CGSize {
        CGSize(width: bodySize.width + topRadius * 2, height: bodySize.height)
    }

    /// Screen-space rect that counts as "on the notch" for hover and clicks.
    var interactiveRect: CGRect {
        let body = geometry.bodyRect(for: shapeSize, top: bodyTop)
        switch phase {
        case .closed where isIsland:
            // Reach up to the screen edge so flicking the pointer to the top still finds it.
            let pill = geometry.bodyRect(for: closedSize, top: bodyTop).insetBy(dx: -6, dy: -4)
            return pill.union(pill.offsetBy(dx: 0, dy: bodyTop))
        case .closed:
            return geometry.bodyRect(for: closedSize).insetBy(dx: -14, dy: 0).offsetBy(dx: 0, dy: -2)
        case .activity(let kind) where !kind.layout.interactive:
            return body.insetBy(dx: -6, dy: 0)
        default:
            return body.insetBy(dx: -4, dy: -4)
        }
    }

    /// Rect a file drag must reach to turn the notch into a drop target.
    var dropProximityRect: CGRect {
        let size = CGSize(width: max(panelWidth, 360) + 80, height: rowHeight + Theme.Size.dropContentHeight + 60)
        return geometry.bodyRect(for: size, top: bodyTop)
    }

    var isExpanded: Bool { phase == .open || phase == .drop }

    // MARK: Pointer

    /// Returns whether the pointer is over the notch or a satellite (the window stops passing
    /// clicks through). Only the body itself opens on hover; satellites wait for a click.
    @discardableResult
    func pointerMoved(to point: CGPoint) -> Bool {
        updateSatelliteHover(at: point)
        // While a satellite card is out, the pill underneath it does not open the panel.
        let inside = interactiveRect.contains(point) && hoveredSatellite == nil
        let clickable = inside || satelliteScreenRects.contains { $0.contains(point) }
        guard inside != isPointerInside else { return clickable }
        isPointerInside = inside
        Log.window.debug("Pointer \(inside ? "entered" : "left") notch, phase=\(String(describing: self.phase), privacy: .public)")
        if inside {
            closeWork?.cancel()
            guard !isOpen, preferences.openTrigger == .hover else { return inside }
            if case .activity(let kind) = phase, kind.layout.interactive { return inside }
            schedule(&openWork, after: Motion.hoverOpenDelay) { [weak self] in self?.open() }
        } else {
            openWork?.cancel()
            guard isOpen, !isDropping else { return clickable }
            schedule(&closeWork, after: Motion.hoverCloseDelay) { [weak self] in self?.close() }
        }
        return clickable
    }

    // MARK: Transitions

    func open(tab: NotchTab? = nil) {
        // The island's Control Center is its right satellite, not a panel tab.
        if let tab, !panelTabs.contains(tab), tab == .controls, showsMusicSatellite {
            if expandedSatellite != .trailing { toggleSatellite(.trailing) }
            return
        }
        openWork?.cancel()
        closeWork?.cancel()
        if let tab { select(tab) }
        guard !isOpen else { return }
        isOpen = true
        satelliteWork?.cancel()
        hoveredSatellite = nil
        // Same transaction as the phase change, so a card folding back and the panel opening move together.
        if expandedSatellite != nil { withAnimation(Motion.open) { expandedSatellite = nil } }
        if preferences.haptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        if activity == .needsYou { selectedTab = .agents }
        apply(Motion.open)
    }

    func close() {
        openWork?.cancel()
        closeWork?.cancel()
        guard isOpen else { return }
        isOpen = false
        apply(Motion.close)
    }

    func toggle() { isOpen ? close() : open() }

    func beginDrop() {
        guard !isDropping else { return }
        isDropping = true
        closeWork?.cancel()
        apply(Motion.open)
    }

    func endDrop() {
        guard isDropping else { return }
        isDropping = false
        if isOpen && !isPointerInside { isOpen = false }
        apply(Motion.close)
    }

    /// Tabs the open panel shows. An island with satellites keeps its Control Center in the right
    /// satellite, so the panel leaves the Controls tab out instead of showing a second one.
    var panelTabs: [NotchTab] {
        preferences.orderedTabs.filter { !(showsMusicSatellite && $0 == .controls) }
    }

    /// The selected tab, or the first shown one when the selection is not in the panel (Controls
    /// selected before switching to island).
    var visibleTab: NotchTab {
        let tabs = panelTabs
        return tabs.contains(selectedTab) ? selectedTab : tabs.first ?? .home
    }

    func select(_ tab: NotchTab) {
        guard tab != selectedTab else { return }
        let all = panelTabs
        let forward = (all.firstIndex(of: tab) ?? 0) > (all.firstIndex(of: selectedTab) ?? 0)
        tabDirection = forward ? .trailing : .leading
        withAnimation(Motion.state) { selectedTab = tab }
    }

    /// Moves one tab left (-1) or right (+1) in the user's order, clamping at the ends.
    func stepTab(by delta: Int) {
        let tabs = panelTabs
        guard tabs.count > 1, delta != 0 else { return }
        guard let current = tabs.firstIndex(of: visibleTab) else {
            select(tabs[0])
            return
        }
        let next = min(max(current + (delta > 0 ? 1 : -1), 0), tabs.count - 1)
        guard next != current else { return }
        select(tabs[next])
    }

    var showsMusicSatellite: Bool { isIsland && preferences.islandSatellites }

    /// Fixture entry point for snapshot rendering.
    func preview(phase: Phase, tab: NotchTab = .home, satellite: SatelliteSide? = nil) {
        self.phase = phase
        selectedTab = tab
        expandedSatellite = satellite
    }

    private func activityChanged(_ kind: ActivityKind?) {
        // On the island the left satellite already is the player; music in the pill would show it twice.
        activity = kind == .music && showsMusicSatellite ? nil : kind
        apply(kind != nil ? Motion.activity : Motion.close)
    }

    private func apply(_ animation: Animation) {
        let next: Phase
        if isDropping {
            next = .drop
        } else if isOpen {
            next = .open
        } else if let activity {
            next = .activity(activity)
        } else {
            next = .closed
        }
        guard next != phase else { return }
        withAnimation(animation) { phase = next }
    }

    private func schedule(_ slot: inout DispatchWorkItem?, after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        slot?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { action() } }
        slot = work
        if delay <= 0 {
            DispatchQueue.main.async(execute: work)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }
}

import SwiftUI

/// The open notch: tab strip left of the camera, actions right of it, content below.
struct ExpandedPanel: View {
    @EnvironmentObject private var model: NotchViewModel
    @EnvironmentObject private var preferences: Preferences
    /// Observed so the Widgets tab appears and disappears with the first and last widget.
    @EnvironmentObject private var widgets: WidgetStore
    @Environment(\.wingContext) private var context

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: context.rowHeight)
            ZStack {
                tabContent
                    .id(model.visibleTab)
                    .transition(tabTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, Theme.Radius.panelPadding)
            .padding(.top, 4)
            .padding(.bottom, Theme.Radius.panelPadding)
            .clipped()
            .onPreferenceChange(PanelExtraHeightKey.self) { extra in
                model.setRequestedPanelExtra(extra, for: model.visibleTab)
            }
        }
    }

    private var header: some View {
        // Everything left of the camera housing must fit in this width.
        let gap = model.headerGap
        let inset = Theme.Radius.panelPadding + model.headerInset
        let side = (model.panelWidth - gap) / 2 - inset
        let tabs = model.panelTabs
        let tabWidth = max(20, min(30, (side - 4 - CGFloat(tabs.count - 1) * 2) / CGFloat(max(1, tabs.count))))
        return HStack(spacing: 0) {
            TabStrip(tabs: tabs, tabWidth: tabWidth)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, inset)
                .condense(delay: Motion.stagger(0))
            Color.clear.frame(width: gap)
            HeaderActions()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, inset)
                .condense(delay: Motion.stagger(1))
        }
        .padding(.top, model.isIsland ? 4 : 0)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch model.visibleTab {
        case .home: HomeTab()
        case .recent: RecentTab()
        case .agents: AgentsTab()
        case .controls: ControlsTab()
        case .widgets: WidgetsTab()
        case .tray: TrayTab()
        case .downloads: DownloadsTab()
        case .clipboard: ClipboardTab()
        case .mirror: MirrorTab()
        }
    }

    private var tabTransition: AnyTransition {
        guard !Motion.reduceMotion else { return .opacity }
        let offset: CGFloat = model.tabDirection == .trailing ? 24 : -24
        return .asymmetric(
            insertion: .modifier(
                active: TabSlide(x: offset, blur: 5, opacity: 0),
                identity: TabSlide(x: 0, blur: 0, opacity: 1)
            ),
            removal: .modifier(
                active: TabSlide(x: -offset * 0.6, blur: 5, opacity: 0),
                identity: TabSlide(x: 0, blur: 0, opacity: 1)
            )
        )
    }
}

private struct TabSlide: ViewModifier {
    let x: CGFloat
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content.offset(x: x).blur(radius: blur).opacity(opacity)
    }
}

/// Icon tabs with a sliding selection pill.
private struct TabStrip: View {
    @EnvironmentObject private var model: NotchViewModel
    @EnvironmentObject private var sessions: AgentSessionStore
    @EnvironmentObject private var tray: TrayStore
    @EnvironmentObject private var cleanup: DownloadCleanup
    @EnvironmentObject private var preferences: Preferences
    let tabs: [NotchTab]
    var tabWidth: CGFloat = 30
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                let selected = model.visibleTab == tab
                Button {
                    model.select(tab)
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(selected ? preferences.accent : Theme.Palette.textTertiary)
                        .frame(width: tabWidth, height: 22)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Theme.Palette.surfaceActive)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .overlay(alignment: .topTrailing) { badge(for: tab) }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle(hoverFill: .clear, cornerRadius: 11, padding: EdgeInsets()))
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .help(tab.title)
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.Palette.surface))
    }

    @ViewBuilder
    private func badge(for tab: NotchTab) -> some View {
        switch tab {
        case .agents where sessions.attention != nil:
            Circle().fill(Theme.Accent.needsYou).frame(width: 6, height: 6).offset(x: -4, y: 3).modifier(PulseDot())
        case .agents where !sessions.running.isEmpty:
            Circle().fill(Theme.Accent.claude).frame(width: 5, height: 5).offset(x: -4, y: 3)
        case .tray where !tray.items.isEmpty:
            Circle().fill(Theme.Accent.tray).frame(width: 5, height: 5).offset(x: -4, y: 3)
        case .downloads where !cleanup.pending.isEmpty:
            Circle().fill(Theme.Accent.download).frame(width: 6, height: 6).offset(x: -4, y: 3).modifier(PulseDot())
        case .downloads where !cleanup.expiring.isEmpty:
            Circle().fill(Theme.Accent.warning).frame(width: 5, height: 5).offset(x: -4, y: 3)
        default:
            EmptyView()
        }
    }
}

private struct HeaderActions: View {
    @EnvironmentObject private var battery: BatteryService

    var body: some View {
        HStack(spacing: 6) {
            if battery.state.hasBattery {
                HStack(spacing: 4) {
                    if battery.state.isPluggedIn {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(battery.state.chargeTint)
                            .transition(.scale(scale: 0.25).combined(with: .opacity))
                    }
                    Text("\(battery.state.percent)%")
                        .font(Theme.Typeface.metric)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .contentTransition(.numericText(value: Double(battery.state.percent)))
                    BatteryGlyph(
                        percent: battery.state.percent,
                        tint: battery.state.tint,
                        charging: battery.state.isCharging
                    )
                    .scaleEffect(0.85)
                }
                .animation(Motion.state, value: battery.state.isPluggedIn)
                .animation(Motion.state, value: battery.state.powerMode)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(battery.state.accessibilityDescription)
                .help(battery.state.powerMode == .automatic ? "" : "\(battery.state.powerMode.title) mode")
            }
            IconButton(symbol: "gearshape.fill", size: 12, tint: Theme.Palette.textSecondary, label: "Settings") {
                SettingsWindowController.shared.show()
            }
        }
    }
}

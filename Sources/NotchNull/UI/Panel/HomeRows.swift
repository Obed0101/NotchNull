import AppKit
import SwiftUI

extension Preferences.HomeRow {
    var tint: Color {
        switch self {
        case .keepAwake: Theme.Accent.awake
        case .upNext: Theme.Accent.calendar
        case .timer: Theme.Accent.timer
        case .system: Theme.Accent.codex
        case .agents: Theme.Accent.claude
        case .network: Theme.Accent.airdrop
        case .battery: Theme.Accent.battery
        case .storage: Theme.Accent.system
        case .toggles: Theme.Accent.tray
        case .clipboard: Theme.Accent.clipboard
        }
    }
}

/// What is left (or used) of each agent's current window; a click opens the Agents tab.
struct AgentLimitsRow: View {
    @EnvironmentObject private var claude: ClaudeUsageService
    @EnvironmentObject private var codex: CodexMonitor
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var model: NotchViewModel

    var body: some View {
        Button {
            if model.panelTabs.contains(.agents) { model.select(.agents) }
        } label: {
            InfoRow(symbol: Preferences.HomeRow.agents.symbol, tint: Preferences.HomeRow.agents.tint, title: "Agents") {
                if limits.isEmpty {
                    Text("No limits yet")
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                } else {
                    ForEach(limits, id: \.provider) { limit in
                        HStack(spacing: 4) {
                            ProviderMark(provider: limit.provider, size: 11)
                            Text("\(Int(shown(limit.window)))%")
                                .font(Theme.Typeface.metric)
                                .foregroundStyle(color(limit.window))
                                .contentTransition(.numericText(value: shown(limit.window)))
                        }
                    }
                    Text(preferences.usageShowsRemaining ? "left" : "used")
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(hoverFill: .clear, padding: EdgeInsets()))
        .accessibilityLabel("Agent limits")
        .help("Open Agents")
    }

    /// The first window of each provider: the one that runs out soonest (5 hours).
    private var limits: [(provider: AgentProvider, window: UsageWindow)] {
        var result: [(AgentProvider, UsageWindow)] = []
        if preferences.claudeUsageEnabled, let window = claude.usage.windows.first { result.append((.claude, window)) }
        if preferences.codexEnabled, let window = codex.usage.windows.first { result.append((.codex, window)) }
        return result
    }

    private func shown(_ window: UsageWindow) -> Double {
        preferences.usageShowsRemaining ? (100 - window.percent).rounded(.down) : window.percent.rounded()
    }

    private func color(_ window: UsageWindow) -> Color {
        switch window.severity {
        case .critical: Theme.Accent.danger
        case .warning: Theme.Accent.warning
        case .normal: Theme.Palette.textPrimary
        }
    }
}

struct BatteryRow: View {
    @EnvironmentObject private var battery: BatteryService

    var body: some View {
        let state = battery.state
        InfoRow(symbol: state.isCharging ? "bolt.fill" : Preferences.HomeRow.battery.symbol, tint: state.tint, title: "Battery") {
            if let detail = detail(state) {
                Text(detail)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
            Text("\(state.percent)%")
                .font(Theme.Typeface.metric)
                .foregroundStyle(Theme.Palette.textPrimary)
                .contentTransition(.numericText(value: Double(state.percent)))
        }
    }

    private func detail(_ state: BatteryState) -> String? {
        if state.isCharged { return "Charged" }
        if state.isCharging, let minutes = state.minutesToFull { return "\(Formatting.minutes(minutes)) to full" }
        if !state.isPluggedIn, let minutes = state.minutesToEmpty { return "\(Formatting.minutes(minutes)) left" }
        return nil
    }
}

struct StorageRow: View {
    @EnvironmentObject private var stats: SystemStatsService

    var body: some View {
        InfoRow(symbol: Preferences.HomeRow.storage.symbol, tint: Preferences.HomeRow.storage.tint, title: "Storage") {
            Text("\(free) free")
                .font(Theme.Typeface.caption.monospacedDigit())
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
        }
    }

    /// Whole gigabytes: the decimals of a 200 GB figure are noise in a glance row.
    private var free: String {
        let bytes = stats.snapshot.diskFree
        return bytes >= 1e9 ? "\(Int(bytes / 1e9)) GB" : Formatting.bytes(bytes)
    }
}

/// Wi-Fi, Bluetooth and Dark Mode as three small switches.
struct TogglesRow: View {
    @EnvironmentObject private var controls: ControlCenterService

    var body: some View {
        InfoRow(symbol: Preferences.HomeRow.toggles.symbol, tint: Preferences.HomeRow.toggles.tint, title: "Controls") {
            toggle(controls.wifiOn ? "wifi" : "wifi.slash", "Wi-Fi", isOn: controls.wifiOn, action: controls.toggleWifi)
            toggle("wave.3.right", "Bluetooth", isOn: controls.bluetoothOn, action: controls.toggleBluetooth)
            toggle("circle.lefthalf.filled", "Dark Mode", isOn: controls.darkMode, action: controls.toggleDarkMode)
        }
        .onAppear { controls.setVisible(true) }
        .onDisappear { controls.setVisible(false) }
    }

    private func toggle(_ symbol: String, _ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isOn ? Color.black : Theme.Palette.textSecondary)
                .frame(width: 28, height: 20)
                .background(Capsule().fill(isOn ? Theme.Palette.textPrimary : Theme.Palette.surfaceHover))
        }
        .buttonStyle(PressableStyle(hoverFill: .clear, cornerRadius: 10, padding: EdgeInsets()))
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .help(label)
    }
}

/// The newest clipboard item, one click from being copied again.
struct ClipboardRow: View {
    @EnvironmentObject private var clipboard: ClipboardService

    var body: some View {
        InfoRow(symbol: Preferences.HomeRow.clipboard.symbol, tint: Preferences.HomeRow.clipboard.tint, title: "Copied") {
            if let item = clipboard.items.first {
                Text(item.preview)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(-1)
                Chip(title: "Copy") { clipboard.copy(item) }
            } else {
                Text("Nothing yet")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }
}

/// A widget's `home` block: its text (and optional bar) as one row; a click runs its action.
struct WidgetHomeRow: View {
    let widget: LoadedWidget

    var body: some View {
        let home = widget.homeRow ?? [:]
        let scope = widget.scope
        let tint = WidgetStyle.color(home["tint"] ?? widget.definition?.tint) ?? Theme.Accent.clipboard
        let row = InfoRow(
            symbol: home["symbol"]?.string ?? widget.definition?.symbol ?? "square.on.square",
            tint: tint,
            title: home["title"].map { Template.text($0, in: scope) } ?? widget.definition?.title ?? widget.id
        ) {
            if let error = widget.error {
                Text("Error")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Accent.warning)
                    .help(error)
            } else {
                if let progress = home["progress"].flatMap({ Template.resolve($0, in: scope)?.double }) {
                    UsageBar(percent: min(max(progress, 0), 1) * 100, tint: tint, height: 4)
                        .frame(width: 34, height: 4)
                }
                Text(Template.text(home["text"], in: scope))
                    .font(Theme.Typeface.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
        }
        if let action = home["action"] {
            Button {
                WidgetStore.shared.perform(action, widget: widget.id, scope: scope)
            } label: {
                row.contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(hoverFill: .clear, padding: EdgeInsets()))
        } else {
            row
        }
    }
}

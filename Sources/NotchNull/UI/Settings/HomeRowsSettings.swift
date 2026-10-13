import SwiftUI

/// Order and visibility of the Home quick list: built-in rows plus every widget with a `home` block.
struct HomeRowsSettings: View {
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var widgets: WidgetStore

    private struct Entry: Identifiable {
        let id: String
        let title: String
        let subtitle: String?
        let symbol: String
        let tint: Color
    }

    var body: some View {
        let widgetRows = widgets.widgets.filter { $0.homeRow != nil }
        let ids = widgetRows.map(\.id)
        let shown = preferences.homeKeys(widgetRows: ids)
        let all = Preferences.HomeRow.allCases.map(\.rawValue) + ids.map { Preferences.widgetRowPrefix + $0 }
        let keys = shown + all.filter { !shown.contains($0) }
        SettingsGroup(
            title: "Home rows",
            footer: "The quick list beside the music player, top to bottom; rows past the panel's height scroll. Ask your agent for more: a widget with a \"home\" block appears here."
        ) {
            ForEach(keys.compactMap { entry(for: $0, widgets: widgetRows) }) { entry in
                let index = shown.firstIndex(of: entry.id)
                SettingsRow(title: entry.title, subtitle: entry.subtitle, symbol: entry.symbol, tint: entry.tint) {
                    Button { preferences.moveHomeKey(entry.id, by: -1, widgetRows: ids) } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.borderless)
                        .disabled(index == nil || index == 0)
                        .accessibilityLabel("Move \(entry.title) up")
                    Button { preferences.moveHomeKey(entry.id, by: 1, widgetRows: ids) } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.borderless)
                        .disabled(index == nil || index == shown.count - 1)
                        .accessibilityLabel("Move \(entry.title) down")
                    Toggle("", isOn: Binding(
                        get: { index != nil },
                        set: { preferences.setHomeKey(entry.id, visible: $0, widgetRows: ids) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .accessibilityLabel(entry.title)
                }
            }
        }
    }

    private func entry(for key: String, widgets: [LoadedWidget]) -> Entry? {
        if let row = Preferences.HomeRow(rawValue: key) {
            return Entry(id: key, title: row.title, subtitle: unavailable(row), symbol: row.symbol, tint: row.tint)
        }
        guard let widget = widgets.first(where: { Preferences.widgetRowPrefix + $0.id == key }) else { return nil }
        let home = widget.homeRow ?? [:]
        return Entry(
            id: key,
            title: home["title"]?.string ?? widget.definition?.title ?? widget.id,
            subtitle: "Widget · \(widget.id).json",
            symbol: home["symbol"]?.string ?? widget.definition?.symbol ?? "square.on.square",
            tint: WidgetStyle.color(home["tint"] ?? widget.definition?.tint) ?? Theme.Accent.clipboard
        )
    }

    /// Why a row that is switched on still does not show.
    private func unavailable(_ row: Preferences.HomeRow) -> String? {
        let enabled = switch row {
        case .upNext: preferences.calendarEnabled
        case .system, .network, .storage: preferences.statsEnabled
        case .agents: preferences.agentsEnabled
        case .battery: preferences.batteryEnabled
        case .clipboard: preferences.clipboardEnabled
        case .keepAwake, .timer, .toggles: true
        }
        return enabled ? nil : "Feature is off"
    }
}

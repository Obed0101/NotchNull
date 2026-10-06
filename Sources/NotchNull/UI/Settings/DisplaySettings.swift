import AppKit
import SwiftUI

struct DisplaySettings: View {
    @EnvironmentObject private var preferences: Preferences
    @State private var displays = NotchDisplay.connected

    private var eligibleIDs: Set<CGDirectDisplayID> {
        Set(DisplaySelection.eligible(displays, mode: preferences.displayMode, selected: preferences.selectedDisplays).map(\.id))
    }

    var body: some View {
        SettingsGroup(title: "Displays", footer: "Automatic shape uses the hardware notch on your MacBook and a floating island on a monitor or iPad via Sidecar. Selections are remembered when a display reconnects. The clipboard shortcut opens on the display under the pointer.") {
            SettingsRow(title: "Show on", symbol: "display", tint: Theme.Accent.system) {
                Picker("Show on", selection: $preferences.displayMode) {
                    ForEach(Preferences.DisplayMode.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 170)
            }
            ForEach(displays) { display in
                SettingsRow(title: display.name,
                    subtitle: "\(Int(display.frame.width)) × \(Int(display.frame.height)) pt · \(display.hasNotch ? "Hardware notch" : "No notch · Automatic uses island")",
                    symbol: display.builtIn ? "laptopcomputer" : "display", tint: Theme.Accent.system) {
                    if preferences.displayMode == .selected {
                        Toggle("Show on \(display.name)", isOn: Binding(
                            get: { preferences.selectedDisplays.contains(display.persistentID) },
                            set: { enabled in
                                preferences.selectedDisplays.removeAll { $0 == display.persistentID }
                                if enabled { preferences.selectedDisplays.append(display.persistentID) }
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    } else {
                        Text(eligibleIDs.contains(display.id) ? "Enabled" : "Off")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
            }
            if preferences.displayMode == .selected {
                ForEach(preferences.selectedDisplays.filter { id in !displays.contains { $0.persistentID == id } }, id: \.self) { id in
                    SettingsRow(title: "Disconnected display", subtitle: id, symbol: "display", tint: Theme.Accent.system) {
                        Button("Forget") { preferences.selectedDisplays.removeAll { $0 == id } }
                    }
                }
                if eligibleIDs.isEmpty {
                    SettingsRow(title: "No connected display selected", subtitle: "Enable a display above to show the notch. Settings stay available from the menu bar.", symbol: "info.circle", tint: Theme.Accent.warning) { EmptyView() }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displays = NotchDisplay.connected
        }
    }
}

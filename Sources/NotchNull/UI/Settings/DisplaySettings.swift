import AppKit
import SwiftUI

/// Settings › Displays: where the notch appears, which shown displays expand for attention, and
/// every connected screen's own switches. Saved selections are keyed by display UUID.
struct DisplaySettings: View {
    @EnvironmentObject private var preferences: Preferences
    @State private var displays = NotchDisplay.connected

    private var eligibleDisplays: [NotchDisplay] {
        DisplaySelection.eligible(displays, mode: preferences.displayMode, selected: preferences.selectedDisplays)
    }

    private var eligibleIDs: Set<CGDirectDisplayID> {
        Set(eligibleDisplays.map(\.id))
    }

    /// The displays that may expand for attention right now, so each switch shows the effective
    /// answer even when All enabled displays or Same as Show on is chosen.
    private var attentionTargetIDs: Set<String> {
        Set(DisplaySelection.attentionEligible(
            displays,
            displayMode: preferences.displayMode,
            selected: preferences.selectedDisplays,
            attentionMode: preferences.attentionDisplayMode,
            attentionSelected: preferences.attentionDisplays
        ).map { $0.persistentID.uppercased() })
    }

    private var disconnectedSelectedDisplays: [String] {
        preferences.selectedDisplays.filter { id in
            !displays.contains { sameIdentity($0.persistentID, id) }
        }
    }

    private var disconnectedAttentionDisplays: [String] {
        preferences.attentionDisplays.filter { id in
            !displays.contains { sameIdentity($0.persistentID, id) }
        }
    }

    private var followsSingleDisplay: Bool {
        preferences.attentionDisplayMode == .followDisplay
            && !AttentionSelection.followsShowOn(
                displayMode: preferences.displayMode,
                attentionMode: preferences.attentionDisplayMode
            )
    }

    var body: some View {
        SettingsGroup(
            title: "Notch",
            footer: "Selections use each display's UUID and survive reconnects, restarts and display-number changes. A saved display that is not connected stays remembered until you forget it. The clipboard shortcut opens on the display under the pointer."
        ) {
            SettingsRow(title: "Show NotchNull on", symbol: "display", tint: Theme.Accent.system) {
                Picker("Show NotchNull on", selection: $preferences.displayMode.animation(Motion.state)) {
                    ForEach(Preferences.DisplayMode.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 190)
            }
            SettingsRow(
                title: "Expand for attention on",
                subtitle: attentionSubtitle,
                symbol: "bell.badge.fill",
                tint: Theme.Accent.warning
            ) {
                Picker("", selection: $preferences.attentionDisplayMode.animation(Motion.state)) {
                    ForEach(Preferences.AttentionDisplayMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 190)
                .accessibilityLabel("Expand for attention on")
            }
        }

        SettingsGroup(
            title: "Displays",
            footer: "Show notch turns one display on or off; if Show NotchNull on is All, Main or Built-in, the first switch moves it to Custom and keeps the current choices. Attention is available only while that display's notch is shown. Hover and manual opening still reveal a shown notch that is not selected for attention. Automatic shape uses the hardware notch on a MacBook and a floating island on a monitor or iPad via Sidecar."
        ) {
            if displays.isEmpty {
                SettingsRow(
                    title: "No displays connected",
                    subtitle: "Connect a display to show the notch. Settings stay available from the menu bar.",
                    symbol: "display.slash",
                    tint: Theme.Accent.warning
                ) { EmptyView() }
            }
            ForEach(displays) { display in
                SettingsRow(
                    title: display.name,
                    subtitle: displaySubtitle(display),
                    symbol: display.builtIn ? "laptopcomputer" : "display",
                    tint: eligibleIDs.contains(display.id) ? Theme.Accent.system : Theme.Palette.textTertiary
                ) {
                    displayControls(display)
                }
            }
            if preferences.displayMode == .selected, eligibleIDs.isEmpty {
                SettingsRow(
                    title: "No connected display selected",
                    subtitle: "Enable a display above to show the notch. Settings stay available from the menu bar.",
                    symbol: "info.circle",
                    tint: Theme.Accent.warning
                ) { EmptyView() }
            }
            ForEach(disconnectedSelectedDisplays, id: \.self) { id in
                SettingsRow(
                    title: "Disconnected display",
                    subtitle: "\(id) · remembered for when it reconnects",
                    symbol: "display.slash",
                    tint: Theme.Accent.warning
                ) {
                    Button("Forget") { forgetSelected(id) }
                }
            }
            ForEach(disconnectedAttentionDisplays, id: \.self) { id in
                SettingsRow(
                    title: "Disconnected attention display",
                    subtitle: "\(id) · remembered for when it reconnects",
                    symbol: "display.slash",
                    tint: Theme.Accent.warning
                ) {
                    Button("Forget") { forgetAttention(id) }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displays = NotchDisplay.connected
        }
    }

    private var attentionSubtitle: String {
        switch preferences.attentionDisplayMode {
        case .enabled:
            return "Every display with a notch shown here expands for alerts."
        case .followDisplay:
            return AttentionSelection.followsShowOn(
                displayMode: preferences.displayMode,
                attentionMode: preferences.attentionDisplayMode
            )
                ? "Every shown notch expands for alerts."
                : "Follows the single display chosen by Show NotchNull on."
        case .selected:
            return "Choose which shown displays expand for alerts. Hover and manual opening still reveal the others."
        }
    }

    private func displaySubtitle(_ display: NotchDisplay) -> String {
        let status = "\(Int(display.frame.width)) × \(Int(display.frame.height)) pt · \(display.hasNotch ? "Hardware notch" : "No notch")"
        guard eligibleIDs.contains(display.id) else {
            return status + "\nNotch is off, so Attention is unavailable."
        }
        if preferences.attentionDisplayMode == .selected {
            return status + "\n" + (isAttentionOn(display) ? "Attention + manual reveal" : "Manual reveal only")
        }
        if followsSingleDisplay {
            let follows = eligibleDisplays.first?.id == display.id
            return status + "\n" + (follows ? "Attention + manual reveal" : "Manual reveal only")
        }
        return status
    }

    @ViewBuilder
    private func displayControls(_ display: NotchDisplay) -> some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack(spacing: 4) {
                ForEach(Array(badges(for: display).enumerated()), id: \.offset) { _, badge in
                    DisplayBadge(text: badge.title, tint: badge.tint)
                }
            }
            HStack(spacing: 12) {
                Toggle("Show notch", isOn: notchBinding(for: display))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 10.5))
                    .fixedSize()
                    .help("Show the notch on \(display.name)")
                    .accessibilityLabel("Show notch on \(display.name)")
                Toggle("Attention", isOn: attentionBinding(for: display))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 10.5))
                    .fixedSize()
                    .tint(Theme.Accent.warning)
                    .disabled(!eligibleIDs.contains(display.id))
                    .help(eligibleIDs.contains(display.id)
                        ? "Expand for attention on \(display.name)"
                        : "Notch is off, so Attention is unavailable.")
                    .accessibilityLabel("Expand for attention on \(display.name)")
            }
        }
    }

    private func badges(for display: NotchDisplay) -> [(title: String, tint: Color)] {
        var badges: [(title: String, tint: Color)] = []
        if displays.first?.id == display.id {
            badges.append(("Main", Theme.Accent.success))
        }
        badges.append(display.builtIn
            ? ("Built-in", Theme.Accent.system)
            : ("External", Theme.Accent.airdrop))
        return badges
    }

    private func notchBinding(for display: NotchDisplay) -> Binding<Bool> {
        Binding(
            get: { eligibleIDs.contains(display.id) },
            set: { enabled in
                let change = DisplaySelection.togglingNotch(
                    display,
                    enabled: enabled,
                    displays: displays,
                    mode: preferences.displayMode,
                    selected: preferences.selectedDisplays
                )
                withAnimation(Motion.state) {
                    preferences.selectedDisplays = change.selected
                    preferences.displayMode = change.mode
                }
            }
        )
    }

    private func isAttentionOn(_ display: NotchDisplay) -> Bool {
        attentionTargetIDs.contains(display.persistentID.uppercased())
    }

    private func attentionBinding(for display: NotchDisplay) -> Binding<Bool> {
        Binding(
            get: { eligibleIDs.contains(display.id) && isAttentionOn(display) },
            set: { enabled in
                let change = DisplaySelection.togglingAttention(
                    display,
                    enabled: enabled,
                    displays: displays,
                    displayMode: preferences.displayMode,
                    selected: preferences.selectedDisplays,
                    attentionMode: preferences.attentionDisplayMode,
                    attentionSelected: preferences.attentionDisplays
                )
                withAnimation(Motion.state) {
                    preferences.attentionDisplays = change.selected
                    preferences.attentionDisplayMode = change.mode
                }
            }
        )
    }

    private func forgetSelected(_ id: String) {
        preferences.selectedDisplays.removeAll { sameIdentity($0, id) }
    }

    private func forgetAttention(_ id: String) {
        preferences.attentionDisplays.removeAll { sameIdentity($0, id) }
    }

    private func sameIdentity(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }
}

private struct DisplayBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.16)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.28)))
    }
}

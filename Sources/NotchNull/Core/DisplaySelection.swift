import AppKit

/// One connected display and the stable identity used by saved selections.
struct NotchDisplay: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let persistentID: String
    let name: String
    let frame: CGRect
    let builtIn: Bool
    let hasNotch: Bool
    let scale: CGFloat

    /// The display's identity across reconnects, restarts and display-number changes.
    static func persistentID(for screen: NSScreen) -> String {
        let id = NotchGeometry.screenID(screen)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "" }
        return CFUUIDCreateString(nil, uuid) as String
    }

    @MainActor
    static var connected: [NotchDisplay] {
        NSScreen.screens.map { screen in
            let id = NotchGeometry.screenID(screen)
            return NotchDisplay(id: id, persistentID: persistentID(for: screen),
                name: screen.localizedName, frame: screen.frame, builtIn: NotchGeometry.isBuiltIn(screen),
                hasNotch: NotchGeometry(screen: screen).hasHardwareNotch, scale: screen.backingScaleFactor)
        }
    }
}

/// One display's switch was toggled: the persisted list and the mode it needs.
struct NotchSelectionChange: Equatable {
    var mode: Preferences.DisplayMode
    var selected: [String]
}

/// One display's attention switch was toggled: the persisted list and the mode it needs.
struct AttentionSelectionChange: Equatable {
    var mode: Preferences.AttentionDisplayMode
    var selected: [String]
}

enum AttentionSelection {
    /// Same as Show on means one target for Built-in, Main and Selected, but every target for All.
    static func followsShowOn(
        displayMode: Preferences.DisplayMode,
        attentionMode: Preferences.AttentionDisplayMode
    ) -> Bool {
        attentionMode == .enabled || (attentionMode == .followDisplay && displayMode == .all)
    }
}

@MainActor
enum DisplaySelection {
    /// NSScreen.main follows keyboard focus; the first screen is the macOS main display.
    static func eligible(_ displays: [NotchDisplay], mode: Preferences.DisplayMode, selected: [String]) -> [NotchDisplay] {
        switch mode {
        case .all: return displays
        case .main: return Array(displays.prefix(1))
        case .builtIn: return displays.first(where: \.builtIn).map { [$0] } ?? Array(displays.prefix(1))
        case .selected:
            let selectedIDs = Set(selected.map { $0.uppercased() })
            return displays.filter { selectedIDs.contains($0.persistentID.uppercased()) }
        }
    }

    static func target(_ displays: [NotchDisplay], pointer: CGPoint) -> CGDirectDisplayID? {
        displays.first { $0.frame.contains(pointer) }?.id
            ?? displays.first(where: \.builtIn)?.id ?? displays.first?.id
    }

    /// `attentionMode` is always relative to the displays selected by `displayMode`/`selected`.
    static func attentionEligible(
        _ allDisplays: [NotchDisplay],
        displayMode: Preferences.DisplayMode,
        selected: [String],
        attentionMode: Preferences.AttentionDisplayMode,
        attentionSelected: [String],
        connected: [NotchDisplay]? = nil
    ) -> [NotchDisplay] {
        let displays = connected ?? allDisplays
        let enabled = eligible(displays, mode: displayMode, selected: selected)
        switch attentionMode {
        case .enabled: return enabled
        case .followDisplay:
            guard AttentionSelection.followsShowOn(
                displayMode: displayMode,
                attentionMode: attentionMode
            ) else { return Array(enabled.prefix(1)) }
            return enabled
        case .selected: return enabled.filter { display in
            attentionSelected.contains { $0.uppercased() == display.persistentID.uppercased() }
        }
        }
    }

    static func allowsAttention(
        displayID: String,
        displays: [NotchDisplay],
        displayMode: Preferences.DisplayMode,
        selected: [String],
        attentionMode: Preferences.AttentionDisplayMode,
        attentionSelected: [String],
        fallbackScreenFrame: CGRect? = nil,
        connected: [NotchDisplay]? = nil
    ) -> Bool {
        let connectedDisplays = connected ?? displays
        let targets = attentionEligible(
            displays, displayMode: displayMode, selected: selected,
            attentionMode: attentionMode, attentionSelected: attentionSelected,
            connected: connectedDisplays
        )
        if !displayID.isEmpty, targets.contains(where: { $0.persistentID.uppercased() == displayID.uppercased() }) { return true }
        // Snapshot and presentation-test models can use a synthetic UUID. Match their geometry only
        // when they are not using an explicit custom selection.
        guard attentionMode != .selected,
              let fallbackScreenFrame,
              let match = connectedDisplays.first(where: { $0.frame == fallbackScreenFrame }) else { return false }
        return targets.contains { $0.persistentID == match.persistentID }
    }

    /// Turns one display's "Show notch" switch into a Custom selection. All, Main and Built-in have
    /// no per-display list, so the currently eligible displays seed it before the toggle applies;
    /// that makes turning a single monitor off discoverable without first choosing Custom.
    static func togglingNotch(
        _ display: NotchDisplay,
        enabled: Bool,
        displays: [NotchDisplay],
        mode: Preferences.DisplayMode,
        selected: [String]
    ) -> NotchSelectionChange {
        let base = mode == .selected
            ? selected
            : disconnectedSaved(selected, displays: displays)
                + eligible(displays, mode: mode, selected: selected).map(\.persistentID)
        var next = base.filter { !sameIdentity($0, display.persistentID) }
        if enabled { next.append(display.persistentID) }
        return NotchSelectionChange(mode: .selected, selected: next)
    }

    /// Turns one display's Attention switch into a Selected attention list. All enabled displays and
    /// Same as Show on have no list of their own, so their current effective targets seed it before
    /// the toggle applies. A display whose notch is off is never added.
    static func togglingAttention(
        _ display: NotchDisplay,
        enabled: Bool,
        displays: [NotchDisplay],
        displayMode: Preferences.DisplayMode,
        selected: [String],
        attentionMode: Preferences.AttentionDisplayMode,
        attentionSelected: [String]
    ) -> AttentionSelectionChange {
        let notchEnabled = eligible(displays, mode: displayMode, selected: selected)
            .contains { sameIdentity($0.persistentID, display.persistentID) }
        guard !enabled || notchEnabled else {
            return AttentionSelectionChange(mode: attentionMode, selected: attentionSelected)
        }
        let base = attentionMode == .selected
            ? attentionSelected
            : disconnectedSaved(attentionSelected, displays: displays)
                + attentionEligible(
                    displays,
                    displayMode: displayMode,
                    selected: selected,
                    attentionMode: attentionMode,
                    attentionSelected: attentionSelected
                ).map(\.persistentID)
        var next = base.filter { !sameIdentity($0, display.persistentID) }
        if enabled { next.append(display.persistentID) }
        return AttentionSelectionChange(mode: .selected, selected: next)
    }

    private static func disconnectedSaved(_ ids: [String], displays: [NotchDisplay]) -> [String] {
        let connected = Set(displays.map { $0.persistentID.uppercased() })
        return ids.filter { !connected.contains($0.uppercased()) }
    }

    private static func sameIdentity(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    /// Only actively disabled connected displays are pruned. Temporarily disconnected displays and
    /// connected displays hidden by the current mode stay remembered for when their notch returns.
    static func pruneAttention(
        _ attentionSelected: [String],
        displays: [NotchDisplay],
        displayMode: Preferences.DisplayMode,
        selected: [String],
        connected: [NotchDisplay]? = nil
    ) -> [String] {
        let connectedDisplays = connected ?? displays
        let enabled = eligible(connectedDisplays, mode: displayMode, selected: selected)
        let enabledIDs = Set(enabled.map { $0.persistentID.uppercased() })
        // All, Main and Built-in hide screens by mode rather than turning their notch off. Only
        // Custom can actively disable a connected screen, so only that mode prunes saved attention.
        let disabled = displayMode == .selected
            ? Set(connectedDisplays.map { $0.persistentID.uppercased() }).subtracting(enabledIDs)
            : []
        return attentionSelected.filter { !disabled.contains($0.uppercased()) }
    }
}

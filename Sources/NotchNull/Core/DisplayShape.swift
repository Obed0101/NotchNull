import Foundation

/// How one display presents the body, after its own override and the global default are combined.
struct DisplayPresentation: Equatable {
    /// The body floats as the island instead of growing out of the notch.
    let island: Bool
    /// The body leaves room for a camera housing, so content keeps clear of the middle.
    let housingGap: Bool
    /// Wings, OSDs and the open panel's header use one row across the middle: the island, or the
    /// notch style on a screen that does not assume a camera housing.
    var spansMiddle: Bool { island || !housingGap }
}

/// One stored override that the per-screen rows do not already cover: a screen that is connected
/// but gets no panel in the current display mode, or one that is not connected at all.
struct OrphanOverride: Identifiable, Equatable {
    /// The display's persistent identifier, which is what the override is keyed by.
    let id: String
    /// The connected screen with this identifier, when there is one.
    let display: NotchDisplay?

    var isConnected: Bool { display != nil }

    /// Named when the screen is here, so the reader can tell the two cases apart.
    var title: String { display?.name ?? "Disconnected display" }

    /// The identifier, and why this row exists when the screen is connected.
    var subtitle: String {
        display == nil ? id : "\(id) · connected, but this display mode gives it no panel"
    }
}

/// Combines the global shape default with a display's own override.
enum DisplayShapeResolver {
    static func resolve(
        default shape: Preferences.ShapeStyle,
        override: Preferences.DisplayShape?,
        hasHardwareNotch: Bool
    ) -> DisplayPresentation {
        let style = override?.style ?? shape
        let island = style == .island || (style == .auto && !hasHardwareNotch)
        // Nothing may be drawn over a camera housing that is really there.
        let housingGap = hasHardwareNotch || (override?.housingGap ?? true)
        return DisplayPresentation(island: island, housingGap: housingGap)
    }

    /// Every stored override that has no row of its own, so it can still be forgotten. The rows come
    /// from `eligible`; an override whose screen is connected but not eligible would otherwise be
    /// unreachable, since filtering against every connected screen drops it from the other list too.
    /// Takes identifiers rather than displays so the rule can be tested without real screens.
    static func orphanOverrides(
        stored: Set<String>,
        connected: [NotchDisplay],
        eligible: Set<String>
    ) -> [OrphanOverride] {
        stored
            .filter { !eligible.contains($0) }
            .sorted()
            .map { id in OrphanOverride(id: id, display: connected.first { $0.persistentID == id }) }
    }

    /// The one-line description of a screen's shape row: its size, the choice it stores, then only
    /// the parts that choice does not already name. Default and Automatic leave the body unnamed, so
    /// the resolved body is added; an explicit Notch or Island is not repeated back at the reader.
    static func subtitle(
        size: String,
        stored: Preferences.ShapeStyle?,
        presentation: DisplayPresentation,
        hasHardwareNotch: Bool
    ) -> String {
        var parts = [size, stored?.title ?? "Default"]
        if stored == nil || stored == .auto {
            parts.append(presentation.island ? "Island" : "Notch")
        }
        if !presentation.island, !hasHardwareNotch, !presentation.housingGap {
            parts.append("no camera housing")
        }
        return parts.joined(separator: " · ")
    }
}

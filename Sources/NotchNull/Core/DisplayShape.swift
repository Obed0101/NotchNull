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
}

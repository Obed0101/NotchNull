import SwiftUI

extension NotchTab {
    /// Extra open-panel content height a tab needs beyond `preferences.panelHeight`.
    /// Agents overflows by a few pixels at the default height (the opencode label
    /// clips and `NotchScroll` picks its scrolling branch), so it gets room for
    /// one more caption line. Other tabs fit and request nothing.
    ///
    /// The view itself mirrors this via `.panelExtraHeight(...)`; the model uses
    /// the larger of the two so sizing stays deterministic before SwiftUI
    /// propagates the preference (previews, snapshots, tests).
    var panelExtraHeight: CGFloat {
        switch self {
        case .agents: 16
        default: 0
        }
    }

    /// Hard cap for live `.panelExtraHeight` requests. The canvas clamp in
    /// `NotchViewModel.bodySize` remains the final bound.
    static let maxRequestedPanelExtra: CGFloat = 32
}

/// Per-view request for a slightly taller open panel. A tab that needs a few
/// more pixels declares e.g. `.panelExtraHeight(16)` on its root; ExpandedPanel
/// forwards the largest request to the model, which grows `bodySize` just
/// enough to avoid scrolling. Kept generic so future tabs can use it without
/// touching the model.
struct PanelExtraHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Request the open panel grow by `height` points while this view is shown.
    func panelExtraHeight(_ height: CGFloat) -> some View {
        preference(key: PanelExtraHeightKey.self, value: height)
    }
}

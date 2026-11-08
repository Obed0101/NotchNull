import SwiftUI

/// The whole quota from 0 to 100% used, cut into one cell per day of the cycle (about 14% each
/// for a week). Usage fills from the left across the cells. A vertical tick marks where the
/// cycle is in time: fill short of the tick is under pace, fill past it is ahead.
struct DayCellBar: View {
    let percent: Double
    let days: Int
    let tint: Color
    /// How far through the whole cycle it is, 0...1. Nil hides the tick when the reading is stale.
    let elapsed: Double?

    private static let gap: CGFloat = 2

    /// How full day `index` is, 0...1.
    static func fill(percent: Double, index: Int, days: Int) -> Double {
        let share = 100 / Double(days)
        return max(0, min(1, (percent - Double(index) * share) / share))
    }

    /// Horizontal position of the tick in a bar of `width`, accounting for the gaps between cells.
    static func tickOffset(elapsed: Double, days: Int, width: CGFloat) -> CGFloat {
        let cell = (width - CGFloat(days - 1) * gap) / CGFloat(days)
        let position = max(0, min(1, elapsed)) * Double(days)
        let index = min(days - 1, Int(position))
        return CGFloat(index) * (cell + gap) + CGFloat(position - Double(index)) * cell
    }

    var body: some View {
        GeometryReader { proxy in
            let cell = max(0, (proxy.size.width - CGFloat(days - 1) * Self.gap) / CGFloat(days))
            ZStack(alignment: .leading) {
                HStack(spacing: Self.gap) {
                    ForEach(0..<days, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2).fill(Theme.Palette.track)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(tint)
                                    .frame(width: cell * Self.fill(percent: percent, index: index, days: days))
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                    }
                }
                .frame(height: 6)
                if let elapsed {
                    Capsule().fill(Theme.Palette.textPrimary)
                        .frame(width: 2, height: 11)
                        .shadow(color: .black.opacity(0.6), radius: 1)
                        .offset(x: max(0, min(proxy.size.width - 2,
                                              Self.tickOffset(elapsed: elapsed, days: days, width: proxy.size.width) - 1)))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 11)
        .accessibilityHidden(true)
    }
}

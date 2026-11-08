import SwiftUI

/// One segment per cycle day, counted from the reset time. Each segment fills with that day's
/// consumption against that day's allowance; amber marks a day that went over. The outlined
/// segment is today. Past days NotchNull did not observe share the known total consumed before
/// today, filled in order from the reset.
struct DayPaceBar: View {
    let pace: DayPace
    let days: [CycleDay]
    /// Total consumed in the cycle so far, from the provider.
    let percent: Double
    let tint: Color
    /// Stale readings drop the "today" outline, which would claim a live position.
    let live: Bool

    private enum Cell { case day(CycleDay), earlier(Double), empty }

    private var cells: [Cell] {
        let today = days.last { $0.day == pace.day }
        let share = 100 / Double(pace.days)
        var unassigned = (today?.baseline ?? percent)
            - days.filter { $0.day < pace.day }.reduce(0) { $0 + $1.used }
        return (0..<pace.days).map { index in
            if index <= pace.day, let entry = days.last(where: { $0.day == index }) { return .day(entry) }
            guard index < pace.day, unassigned > 0.05 else { return .empty }
            let fill = min(1, unassigned / share)
            unassigned -= share
            return .earlier(fill)
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Theme.Palette.track.opacity(index > pace.day ? 0.5 : 1)
                        switch cell {
                        case .day(let entry):
                            Rectangle()
                                .fill(entry.over ? Theme.Accent.warning : tint)
                                .frame(width: proxy.size.width * entry.fraction)
                        case .earlier(let fill):
                            Rectangle().fill(tint)
                                .frame(width: proxy.size.width * fill)
                        case .empty:
                            EmptyView()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                }
                .overlay(RoundedRectangle(cornerRadius: 2.5)
                    .strokeBorder(live && index == pace.day ? Theme.Palette.textPrimary.opacity(0.85) : .clear, lineWidth: 1)
                    .padding(-1.5))
            }
        }
        .frame(height: 6)
        .padding(.vertical, 1.5)
        .accessibilityHidden(true)
    }
}

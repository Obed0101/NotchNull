import SwiftUI

/// One segment per cycle day, counted from the reset time. Each segment fills with that day's
/// consumption against that day's allowance; amber marks a day that went over. The outlined
/// segment is today. Usage from days NotchNull could not measure exactly fills the past days in
/// order from the reset.
struct DayPaceBar: View {
    let pace: DayPace
    let days: [CycleDay]
    /// Total consumed in the cycle so far, from the provider.
    let percent: Double
    let tint: Color
    /// Stale readings drop the "today" outline, which would claim a live position.
    let live: Bool

    enum Cell: Equatable { case day(CycleDay), earlier(Double), empty }

    /// Days with an exact total draw their own usage. Everything else consumed before today
    /// (days not seen, or seen only in part) is one known pool filled in order from the reset,
    /// so the bar never loses quota the provider reports as already used.
    static func layout(pace: DayPace, days: [CycleDay], percent: Double) -> [Cell] {
        let today = days.last { $0.day == pace.day }
        let exact = { (index: Int) in days.last { $0.day == index && $0.complete == true } }
        var pool = max(0, (today?.baseline ?? percent)
            - (0..<pace.day).compactMap(exact).reduce(0) { $0 + $1.used })
        let share = 100 / Double(pace.days)
        return (0..<pace.days).map { index in
            if index == pace.day { return today.map(Cell.day) ?? .empty }
            if index > pace.day { return .empty }
            if let entry = exact(index) { return .day(entry) }
            guard pool > 0.05 else { return .empty }
            let fill = min(1, pool / share)
            pool -= share
            return .earlier(fill)
        }
    }

    private var cells: [Cell] { Self.layout(pace: pace, days: days, percent: percent) }

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

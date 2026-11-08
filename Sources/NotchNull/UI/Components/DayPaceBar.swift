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

    enum Cell: Equatable {
        case day(CycleDay)
        /// Usage from a day NotchNull could not measure exactly, against that day's allowance.
        /// `proven` is the part of the amount recorded for that day itself; only it can show an overspend.
        case earlier(amount: Double, allowance: Double, proven: Double)
        case empty

        var fraction: Double {
            switch self {
            case .day(let day): day.fraction
            case .earlier(let amount, let allowance, _): allowance > 0 ? min(1, amount / allowance) : (amount > 0 ? 1 : 0)
            case .empty: 0
            }
        }
        var over: Bool {
            switch self {
            case .day(let day): day.over
            case .earlier(_, let allowance, let proven): proven > allowance + 0.05
            case .empty: false
            }
        }
    }

    /// Days with an exact total draw their own usage. Usage from every other past day (not seen,
    /// or seen only in part) starts from what was recorded for it, a lower bound that keeps a
    /// proven overspend amber, and the unmeasured remainder fills the rest in order from the
    /// reset, so the bar never loses quota the provider reports as already used.
    static func layout(pace: DayPace, days: [CycleDay], percent: Double) -> [Cell] {
        let today = days.last { $0.day == pace.day }
        let recorded = { (index: Int) in days.last { $0.day == index } }
        let exact = { (index: Int) in recorded(index).flatMap { $0.complete == true ? $0 : nil } }
        let open = (0..<pace.day).filter { exact($0) == nil }
        let share = 100 / Double(pace.days)
        let allowance = { (index: Int) in recorded(index)?.allowance ?? share }
        var amount = Dictionary(uniqueKeysWithValues: open.map { ($0, recorded($0)?.used ?? 0) })
        var pool = max(0, (today?.baseline ?? percent)
            - (0..<pace.day).compactMap(exact).reduce(0) { $0 + $1.used }
            - amount.values.reduce(0, +))
        for index in open {
            let take = min(pool, max(0, allowance(index) - amount[index, default: 0]))
            amount[index, default: 0] += take
            pool -= take
        }
        // Whatever still does not fit was spent before today, so it lands on the last of them, but
        // never as an overspend: the split between those days and today's untracked hours is unknown.
        if pool > 0.05, let last = open.last { amount[last, default: 0] += pool }
        return (0..<pace.days).map { index in
            if index == pace.day { return today.map(Cell.day) ?? .empty }
            if index > pace.day { return .empty }
            if let entry = exact(index) { return .day(entry) }
            let used = amount[index, default: 0]
            return used > 0.05 ? .earlier(amount: used, allowance: allowance(index), proven: recorded(index)?.used ?? 0) : .empty
        }
    }

    private var cells: [Cell] { Self.layout(pace: pace, days: days, percent: percent) }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Theme.Palette.track.opacity(index > pace.day ? 0.5 : 1)
                        Rectangle()
                            .fill(cell.over ? Theme.Accent.warning : tint)
                            .frame(width: proxy.size.width * cell.fraction)
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

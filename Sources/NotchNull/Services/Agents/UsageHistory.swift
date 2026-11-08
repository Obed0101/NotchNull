import Foundation

/// Quota deltas, not tokens: cache and model pricing make token totals unsuitable for budgeting.
struct UsageHistory: Codable {
    struct Reading: Codable {
        var date: Date
        var percent: Double
        var reset: Date
        var duration: TimeInterval
    }
    struct Interval: Codable {
        var start: Date
        var end: Date
        var used: Double
    }
    var last: Reading?
    var intervals: [Interval] = []

    mutating func record(_ window: UsageWindow, at date: Date, now: Date) -> Bool {
        guard let reset = window.resetsAt, let duration = window.duration,
              duration >= 86_400, duration <= 35 * 86_400,
              window.percent.isFinite, date <= now, now.timeIntervalSince(date) <= 1200,
              reset > date, reset.timeIntervalSince(date) <= duration + 60,
              last.map({ date > $0.date }) ?? true else { return false }
        let reading = Reading(date: date, percent: window.percent, reset: reset, duration: duration)
        if let previous = last {
            if previous.duration != duration { intervals = [] }
            // Never spread a long offline gap across presumed working hours or bridge a reset.
            let gap = date.timeIntervalSince(previous.date)
            if previous.duration == duration, abs(previous.reset.timeIntervalSince(reset)) < 60,
               gap <= 3600, window.percent >= previous.percent {
                let used = window.percent - previous.percent
                // Coalesce same-hour samples, so frequent log publications cannot grow the file
                // or forecast work without bound. Keep local-hour boundaries for the model.
                if let tail = intervals.last, tail.end == previous.date,
                   Calendar.current.isDate(tail.start, equalTo: date.addingTimeInterval(-0.001), toGranularity: .hour),
                   date.timeIntervalSince(tail.start) <= 3600 {
                    intervals[intervals.count - 1].end = date
                    intervals[intervals.count - 1].used += used
                } else {
                    intervals.append(Interval(start: previous.date, end: date, used: used))
                }
            } else if abs(previous.reset.timeIntervalSince(reset)) < 60, window.percent < previous.percent {
                // A correction/account change invalidates the learned scale.
                intervals = []
            }
        }
        last = reading
        intervals.removeAll { $0.end < now.addingTimeInterval(-28 * 86_400) }
        return true
    }

    /// Each local hour needs three hours of actual observations on at least three dates.
    /// Missing hours are unknown, never silently learned as zero consumption.
    func hourlyRates(calendar: Calendar) -> [Double]? {
        var seconds = Array(repeating: 0.0, count: 24)
        var usage = Array(repeating: 0.0, count: 24)
        var days = Array(repeating: Set<Date>(), count: 24)
        for interval in intervals {
            let length = interval.end.timeIntervalSince(interval.start)
            guard length > 0, length <= 3600, interval.used >= 0, interval.used.isFinite else { continue }
            var cursor = interval.start
            while cursor < interval.end {
                guard let hour = calendar.dateInterval(of: .hour, for: cursor) else { return nil }
                let end = min(interval.end, hour.end)
                guard end > cursor else { return nil }
                let index = calendar.component(.hour, from: cursor)
                let span = end.timeIntervalSince(cursor)
                seconds[index] += span
                usage[index] += interval.used * span / length
                days[index].insert(calendar.startOfDay(for: cursor))
                cursor = end
            }
        }
        guard seconds.allSatisfy({ $0 >= 3 * 3600 - 1 }), days.allSatisfy({ $0.count >= 3 }) else { return nil }
        return (0..<24).map { usage[$0] / seconds[$0] * 3600 }
    }

    func forecast(_ window: UsageWindow, at now: Date, calendar: Calendar = .current) -> UsageForecast? {
        guard let last, now.timeIntervalSince(last.date) >= 0, now.timeIntervalSince(last.date) <= 1200,
              let reset = window.resetsAt, reset > now, reset.timeIntervalSince(now) <= 35 * 86_400,
              abs(last.reset.timeIntervalSince(reset)) < 60, last.percent == window.percent,
              last.duration == window.duration, window.percent < 100,
              let rates = hourlyRates(calendar: calendar) else { return nil }
        var cursor = now
        var expected = 0.0
        var exhaustion: Date?
        while cursor < reset {
            guard let hour = calendar.dateInterval(of: .hour, for: cursor) else { return nil }
            let end = min(reset, hour.end)
            guard end > cursor else { return nil }
            let rate = rates[calendar.component(.hour, from: cursor)] / 3600
            let amount = rate * end.timeIntervalSince(cursor)
            if exhaustion == nil, rate > 0, window.percent + expected + amount >= 100 {
                exhaustion = cursor.addingTimeInterval((100 - window.percent - expected) / rate)
            }
            expected += amount
            cursor = end
        }
        return UsageForecast(dailyUse: rates.reduce(0, +), exhaustion: exhaustion.flatMap { $0 < reset ? $0 : nil })
    }
}

struct UsageForecast {
    let dailyUse: Double
    let exhaustion: Date?
}

extension UsageWindow {
    /// A spending allowance, independent of the partial first day's consumption rate.
    func dailyBudget(at now: Date) -> Double? {
        guard let duration, duration >= 86_400, let reset = resetsAt, reset > now,
              reset.timeIntervalSince(now) <= duration + 60 else { return nil }
        return (100 - percent) / max(1, reset.timeIntervalSince(now) / 86_400)
    }
}

@MainActor
final class UsageHistoryStore {
    private var histories: [String: UsageHistory] = [:]
    private let url: URL?
    private let writer = DispatchQueue(label: "NotchNull.usage-history", qos: .utility)

    init(url: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("NotchNull/usage-history.json")) {
        self.url = url
        if let url, let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([String: UsageHistory].self, from: data) {
            histories = saved.filter { $0.value.last.map { Date().timeIntervalSince($0.date) <= 28 * 86_400 } ?? false }
        }
    }

    static func key(provider: String, plan: String?, window: UsageWindow) -> String {
        // JSON encoding avoids delimiter collisions without storing account identifiers.
        String(data: try! JSONEncoder().encode([provider, plan ?? "", window.id]), encoding: .utf8)!
    }

    func record(provider: String, plan: String?, windows: [UsageWindow], updatedAt: Date?, state: ProviderUsage.State, now: Date = Date()) {
        guard state == .ready, let updatedAt else { return }
        var changed = false
        for window in windows {
            let key = Self.key(provider: provider, plan: plan, window: window)
            var history = histories[key] ?? UsageHistory()
            if history.record(window, at: updatedAt, now: now) {
                histories[key] = history
                changed = true
            }
        }
        guard changed else { return }
        histories = histories.filter { $0.value.last.map { now.timeIntervalSince($0.date) <= 28 * 86_400 } ?? false }
        guard let url else { return }
        let snapshot = histories
        writer.async {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            } catch { /* Forecasts remain usable in memory if local storage is unavailable. */ }
        }
    }

    func forecast(provider: String, plan: String?, window: UsageWindow, at now: Date) -> UsageForecast? {
        histories[Self.key(provider: provider, plan: plan, window: window)]?.forecast(window, at: now)
    }
}

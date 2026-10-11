import Foundation

/// Explicit, credential-free export from MendCode. Timestamps are Unix milliseconds.
enum ClaudeSharedUsage {
    static var url: URL { Constants.Paths.support.appendingPathComponent("mendcode-usage.json") }

    static func read(at url: URL = url, now: Date = Date()) -> ProviderUsage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 64_000, let data = try? Data(contentsOf: url) else {
            return unavailable()
        }
        return parse(data, now: now)
    }

    static func unavailable() -> ProviderUsage {
        ProviderUsage(provider: .claude, state: .unavailable("Waiting for MendCode usage"))
    }

    static func parse(_ data: Data, now: Date = Date()) -> ProviderUsage {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["version"] as? Int == 1, object["source"] as? String == "mendcode",
              let rows = object["quota"] as? [[String: Any]] else { return unavailable() }
        var selected: [String: (window: UsageWindow, observed: Date)] = [:]
        for row in rows {
            guard row["provider"] as? String == "claude",
                  let key = row["window"] as? String, ["5h", "7d"].contains(key),
                  let percent = row["usedPercent"] as? Double, percent.isFinite, (0...100).contains(percent),
                  let observedMS = row["observedAt"] as? Double, observedMS.isFinite,
                  let resetMS = row["resetsAt"] as? Double, resetMS.isFinite else { continue }
            let observed = Date(timeIntervalSince1970: observedMS / 1000)
            let reset = Date(timeIntervalSince1970: resetMS / 1000)
            guard observed <= now.addingTimeInterval(60), observed.timeIntervalSince1970 > 0,
                  reset > now, reset > observed else { continue }
            if let prior = selected[key], prior.observed >= observed { continue }
            selected[key] = (UsageWindow(id: key, label: key == "5h" ? "5 hours" : "Week",
                                        percent: percent, resetsAt: reset,
                                        duration: key == "5h" ? 5 * 3600 : 7 * 86400), observed)
        }
        let readings = ["5h", "7d"].compactMap { selected[$0] }
        guard let oldest = readings.map(\.observed).min() else { return unavailable() }
        let stale = now.timeIntervalSince(oldest) > 20 * 60
        return ProviderUsage(provider: .claude, windows: readings.map(\.window), updatedAt: oldest,
                             state: stale ? .unavailable("Last known MendCode limits · awaiting refresh") : .ready)
    }
}

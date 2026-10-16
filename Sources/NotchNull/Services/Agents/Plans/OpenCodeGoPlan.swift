import Foundation
import SwiftUI

/// OpenCode Go subscription: rolling 5-hour, weekly and monthly usage from OpenCode's Go usage API,
/// with the key OpenCode itself signed in with.
struct OpenCodeGoPlan: PlanProvider {
    static let planID = "opencode-go"
    let id = OpenCodeGoPlan.planID
    let title = "OpenCode Go"
    let monogram = "Go"
    var tint: Color { Theme.Accent.opencode }

    func credential(in sources: PlanCredentialSources) -> PlanCredential? {
        // An explicit environment key is an override and names its own source.
        if let found = sources.env(["OPENCODE_API_KEY"]) {
            return PlanCredential(key: found.value, source: found.name)
        }
        // The account OpenCode is signed in with, when the user allowed reading it.
        if case .account(let token, let label) = sources.openCodeAccount {
            return PlanCredential(key: token, source: label.isEmpty ? "OpenCode · active account" : "OpenCode · \(label)")
        }
        // Legacy fallback: the old auth.json key under either provider id.
        if let found = sources.openCodeKey(["opencode-go", "opencode"]) {
            return PlanCredential(key: found.key, source: "OpenCode")
        }
        return nil
    }

    func fetch(_ credential: PlanCredential) async throws -> PlanSnapshot {
        let response = try await PlanHTTP.get(URL(string: "https://opencode.ai/zen/go/v1/usage")!, bearer: credential.key)
        switch response.status {
        case 200:
            return try Self.parse(response.data)
        case 401:
            throw PlanError.signedOut("Key rejected by OpenCode")
        case 403:
            // `EntitlementError`: a valid key on an account without Go.
            throw PlanError.noSubscription
        default:
            throw PlanError.unavailable("OpenCode returned \(response.status)")
        }
    }

    /// `{"usage": {"rolling": {"percent": 3, "resetInSec": 18100}, "weekly": {…}, "monthly": {…}}}`,
    /// percentages in 0…100.
    static func parse(_ data: Data, now: Date = Date()) throws -> PlanSnapshot {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let usage = root["usage"] as? [String: Any] else {
            throw PlanError.unavailable("Unreadable OpenCode response")
        }
        let known: [(key: String, label: String, duration: TimeInterval)] = [
            ("rolling", "5 hours", 5 * 3600), ("weekly", "Week", 7 * 86_400), ("monthly", "Month", 30 * 86_400),
        ]
        let windows = known.compactMap { entry -> UsageWindow? in
            guard let window = usage[entry.key] as? [String: Any],
                  let percent = ["percent", "usagePercent", "usedPercent"].lazy.compactMap({ PlanJSON.double(window[$0]) }).first else { return nil }
            let reset = PlanJSON.double(window["resetInSec"]).map { now.addingTimeInterval($0) }
                ?? ["resetsAt", "resetAt"].lazy.compactMap { PlanJSON.date(window[$0]) }.first
            return UsageWindow(id: "opencode-\(entry.key)", label: entry.label, percent: percent, resetsAt: reset, duration: entry.duration)
        }
        guard !windows.isEmpty else { throw PlanError.noSubscription }
        return PlanSnapshot(plan: nil, windows: windows)
    }
}

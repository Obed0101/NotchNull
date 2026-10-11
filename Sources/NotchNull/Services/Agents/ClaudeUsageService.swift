import Combine
import Foundation
import SwiftUI

/// Claude plan usage from the same OAuth usage endpoint Claude Code's `/usage` reads.
/// The access token is read from Claude Code's keychain item through `/usr/bin/security`, only
/// after the user allows it (macOS may ask once, depending on the item's access list), and is
/// never refreshed here: refreshing would rotate Claude Code's own credentials.
@MainActor
final class ClaudeUsageService: ObservableObject {
    @Published private(set) var usage = ProviderUsage.placeholder(.claude)

    private struct Credentials {
        let accessToken: String
        let expiresAt: Date?
        let plan: String?
    }

    private var credentials: Credentials?
    private var timer: Timer?
    private var inFlight = false
    /// After a 429 the endpoint is left alone until this date, doubling each time it repeats.
    private var retryNotBefore: Date?
    private var rateLimitStrikes = 0
    private var warnedWindows: Set<String> = []
    private var cancellables: Set<AnyCancellable> = []
    var onWarning: ((String, UsageWindow) -> Void)?

    func start() {
        Preferences.shared.$claudeUsageEnabled
            .combineLatest(Preferences.shared.$keychainAllowed)
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled, allowed in
                guard let self else { return }
                if !enabled {
                    pause()
                } else if !allowed {
                    // The keychain is only read once the user allows it, so macOS never asks unprompted.
                    pause()
                    update(state: .signedOut(Self.keychainConsentMessage))
                } else {
                    resume()
                }
            }
            .store(in: &cancellables)
    }

    static let keychainConsentMessage = "Allow NotchNull to read Claude Code's sign-in to see limits"

    /// Fixture entry point for snapshot rendering.
    func preview(_ usage: ProviderUsage) { self.usage = usage }

    private func resume() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Constants.Agents.claudeUsageInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    private func pause() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard !inFlight else { return }
        if let retryNotBefore, retryNotBefore > Date() { return }
        inFlight = true
        Task {
            defer { inFlight = false }
            if credentials == nil || (credentials?.expiresAt.map { $0 < Date() } ?? false) {
                credentials = await Self.readCredentials()
            }
            guard let credentials else {
                update(state: .signedOut("Sign in to Claude Code to see limits"))
                return
            }
            if let expiry = credentials.expiresAt, expiry < Date() {
                update(state: .signedOut("Open Claude Code to refresh sign-in"))
                self.credentials = nil
                return
            }
            await fetch(with: credentials)
        }
    }

    private func fetch(with credentials: Credentials) async {
        var request = URLRequest(url: Constants.Agents.claudeUsageURL, timeoutInterval: 15)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Constants.Agents.claudeOAuthBeta, forHTTPHeaderField: "anthropic-beta")
        request.setValue("NotchNull/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200:
                rateLimitStrikes = 0
                retryNotBefore = nil
                apply(try Self.parse(data), plan: credentials.plan)
            case 401, 403:
                self.credentials = nil
                update(state: .signedOut("Open Claude Code to refresh sign-in"))
            case 429:
                let retryAfter = ((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
                rateLimitStrikes += 1
                let wait = retryAfter ?? min(Constants.Agents.claudeUsageMaxBackoff, Constants.Agents.claudeUsageInterval * pow(2, Double(rateLimitStrikes)))
                retryNotBefore = Date().addingTimeInterval(wait)
                Log.agents.notice("Claude usage endpoint rate limited; retrying in \(Int(wait), privacy: .public)s")
                // Keep the last good numbers; with none yet, say why instead of loading forever.
                update(state: .unavailable(Self.rateLimitMessage))
            default:
                update(state: .unavailable("Usage service returned \(status)"))
            }
        } catch {
            Log.agents.error("Claude usage request failed: \(error.localizedDescription, privacy: .public)")
            update(state: .unavailable("Offline · limits may be out of date"))
        }
    }

    private func update(state: ProviderUsage.State) {
        withAnimation(Motion.state) { usage.state = state }
    }

    nonisolated static let rateLimitMessage = "Claude rate limited · retrying automatically"

    private func apply(_ parsed: (windows: [UsageWindow], breakdown: [UsageShare]), plan: String?) {
        withAnimation(Motion.state) {
            usage = ProviderUsage(
                provider: .claude,
                plan: plan,
                windows: parsed.windows,
                breakdown: parsed.breakdown,
                updatedAt: Date(),
                state: .ready
            )
        }
        for window in parsed.windows {
            if window.severity != .normal, warnedWindows.insert(window.warningKey(provider: "Claude")).inserted {
                onWarning?("Claude", window)
            }
        }
    }

    // MARK: Parsing

    nonisolated static func parse(_ data: Data) throws -> (windows: [UsageWindow], breakdown: [UsageShare]) {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        var windows: [UsageWindow] = []
        if let limits = json["limits"] as? [[String: Any]] {
            for limit in limits {
                guard let kind = limit["kind"] as? String, let percent = (limit["percent"] as? NSNumber)?.doubleValue else { continue }
                let scopeName = ((limit["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
                let group = limit["group"] as? String
                let label: String
                let duration: TimeInterval?
                switch group ?? kind {
                case "session": label = "5 hours"; duration = 5 * 3600
                case "weekly": label = scopeName.map { "Week · \($0)" } ?? "Week"; duration = 7 * 86400
                default: label = scopeName ?? kind.replacingOccurrences(of: "_", with: " ").capitalized; duration = nil
                }
                // Scoped weekly limits at 0% add noise; show them once they carry signal.
                if kind == "weekly_scoped" && percent < 1 { continue }
                let severity = UsageWindow.Severity(rawValue: (limit["severity"] as? String) ?? "") ?? nil
                windows.append(UsageWindow(
                    id: kind + (scopeName ?? ""),
                    label: label,
                    percent: percent,
                    resetsAt: parseDate(limit["resets_at"]),
                    duration: duration,
                    severity: severity == .normal ? nil : severity
                ))
            }
        }
        if windows.isEmpty {
            let legacy: [(String, String, TimeInterval)] = [
                ("five_hour", "5 hours", 5 * 3600), ("seven_day", "Week", 7 * 86400),
                ("seven_day_opus", "Week · Opus", 7 * 86400), ("seven_day_sonnet", "Week · Sonnet", 7 * 86400),
            ]
            for (key, label, duration) in legacy {
                guard let entry = json[key] as? [String: Any],
                      let utilization = (entry["utilization"] as? NSNumber)?.doubleValue else { continue }
                windows.append(UsageWindow(id: key, label: label, percent: utilization, resetsAt: parseDate(entry["resets_at"]), duration: duration))
            }
        }
        var breakdown: [UsageShare] = []
        if let rows = (json["seven_day_breakdown"] as? [String: Any])?["rows"] as? [[String: Any]] {
            breakdown = rows.compactMap { row in
                guard let key = row["key"] as? String, let percent = (row["percent"] as? NSNumber)?.doubleValue else { return nil }
                return UsageShare(id: key, label: (row["display_name"] as? String) ?? key, percent: percent)
            }
        }
        return (windows, breakdown)
    }

    private nonisolated static func parseDate(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private nonisolated static func readCredentials() async -> Credentials? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
                process.arguments = ["find-generic-password", "-s", Constants.Agents.claudeKeychainService, "-w"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    guard process.terminationStatus == 0,
                          let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let oauth = json["claudeAiOauth"] as? [String: Any],
                          let token = oauth["accessToken"] as? String else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let expiry = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
                    let plan = (oauth["subscriptionType"] as? String).map(planName)
                    continuation.resume(returning: Credentials(accessToken: token, expiresAt: expiry, plan: plan))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private nonisolated static func planName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "max": "Max"
        case "pro": "Pro"
        case "team": "Team"
        case "enterprise": "Enterprise"
        default: raw.capitalized
        }
    }
}

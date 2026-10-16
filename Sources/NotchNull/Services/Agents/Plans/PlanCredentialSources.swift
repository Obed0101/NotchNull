import Foundation

/// Places where coding tools keep the keys for these subscriptions. Read-only: NotchNull never
/// writes, copies or refreshes any of them.
struct PlanCredentialSources: Sendable {
    /// The app's environment (set when NotchNull is started from a terminal).
    var environment: [String: String] = [:]
    /// `~/.local/share/opencode/auth.json`: provider id → its entry (`key`, or `refresh` for OAuth).
    var openCode: [String: [String: String]] = [:]
    /// The `env` block of `~/.claude/settings.json`, where a GLM, Kimi or MiniMax plan is often
    /// wired into Claude Code through `ANTHROPIC_BASE_URL`.
    var claudeEnvironment: [String: String] = [:]
    /// GitHub OAuth tokens saved by the Copilot editor plugins.
    var copilotTokens: [String] = []
    /// The OpenCode Console account resolved through `opencode auth export`, when the user allowed
    /// it. Nil keeps the legacy environment and `auth.json` behavior only.
    var openCodeAccount: OpenCodeAuthExport.Selection?

    /// Reads the local sources and — only when `accountUsageAllowed` — the active OpenCode account.
    /// `accountExport` is injected so a test can prove the export is never run without consent.
    static func load(
        home: URL = Constants.Paths.home,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        accountUsageAllowed: Bool = false,
        accountExport: (URL, [String: String]) -> OpenCodeAuthExport.Selection = { home, environment in
            OpenCodeAuthExport.resolve(home: home, environment: environment)
        }
    ) -> PlanCredentialSources {
        var sources = PlanCredentialSources(environment: environment)
        if accountUsageAllowed { sources.openCodeAccount = accountExport(home, environment) }
        if let auth = readJSON(home.appendingPathComponent(".local/share/opencode/auth.json")) {
            for (provider, entry) in auth {
                guard let entry = entry as? [String: Any] else { continue }
                sources.openCode[provider] = entry.compactMapValues { $0 as? String }
            }
        }
        if let settings = readJSON(home.appendingPathComponent(".claude/settings.json")),
           let env = settings["env"] as? [String: Any] {
            sources.claudeEnvironment = env.compactMapValues { $0 as? String }
        }
        for name in ["apps.json", "hosts.json"] {
            guard let entries = readJSON(home.appendingPathComponent(".config/github-copilot/\(name)")) else { continue }
            for (host, entry) in entries where host.hasPrefix("github.com") {
                if let token = (entry as? [String: Any])?["oauth_token"] as? String { sources.copilotTokens.append(token) }
            }
        }
        return sources
    }

    /// The first non-empty environment variable among `names`.
    func env(_ names: [String]) -> (name: String, value: String)? {
        for name in names {
            if let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return (name, value) }
        }
        return nil
    }

    /// The API key OpenCode stores for the first of `providers` that has one.
    func openCodeKey(_ providers: [String]) -> (provider: String, key: String)? {
        for provider in providers {
            if let key = openCode[provider]?["key"], !key.isEmpty { return (provider, key) }
        }
        return nil
    }

    /// Claude Code's token when its base URL points at one of `hosts`, with the matched host.
    func claudeKey(forHosts hosts: [String]) -> (host: String, key: String)? {
        guard let base = claudeEnvironment["ANTHROPIC_BASE_URL"].flatMap(URL.init(string:))?.host?.lowercased(),
              let host = hosts.first(where: { base == $0 || base.hasSuffix(".\($0)") }),
              let key = claudeEnvironment["ANTHROPIC_AUTH_TOKEN"] ?? claudeEnvironment["ANTHROPIC_API_KEY"],
              !key.isEmpty else { return nil }
        return (host, key)
    }

    private static func readJSON(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

import Combine
import Foundation
import SwiftUI

/// Wires the agent services together and owns the latest usage warning shown in the notch.
@MainActor
final class AgentHub: ObservableObject {
    struct Warning: Equatable {
        let provider: String
        let window: UsageWindow
    }

    let sessions = AgentSessionStore()
    let claudeUsage = ClaudeUsageService()
    let claudeTokens = ClaudeTokenStats()
    let plans = PlanUsageService()
    let codex: CodexMonitor
    let opencode: OpencodeMonitor
    private(set) lazy var claudeTranscripts = ClaudeTranscriptMonitor(store: sessions)

    @Published private(set) var warning: Warning?
    @Published private(set) var hooksInstalled = ClaudeHookInstaller.isInstalled
    @Published private(set) var hookError: String?
    @Published private(set) var opencodePluginInstalled = OpencodePluginInstaller.isInstalled
    @Published private(set) var opencodePluginError: String?

    private var server: AgentEventServer?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        codex = CodexMonitor(store: sessions)
        opencode = OpencodeMonitor(store: sessions)
    }

    func start() {
        let warn: (String, UsageWindow) -> Void = { [weak self] provider, window in
            self?.warning = Warning(provider: provider, window: window)
            ActivityCenter.shared.post(.usageWarning, for: Constants.Durations.usageWarning)
            ActivityLog.shared.add(
                symbol: "gauge.with.dots.needle.67percent", tint: Theme.Accent.warning,
                title: "\(provider) \(window.label): \(Int((100 - window.percent).rounded()))% left", detail: Formatting.usageSummary(window)
            )
        }
        claudeUsage.onWarning = warn
        codex.onWarning = warn
        plans.onWarning = warn

        let handler = ClaudeHookHandler(store: sessions)
        let opencodeHandler = OpencodeHookHandler(store: sessions)
        let server = AgentEventServer(token: ClaudeHookInstaller.token()) { request in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard Preferences.shared.agentsEnabled else { return }
                    if request.path == "/opencode" {
                        opencodeHandler.handle(request)
                    } else {
                        handler.handle(request)
                    }
                }
            }
        }
        server.apiHandler = { request in MainActor.assumeIsolated { NotchAPI.handle(request) } }
        server.start(port: Constants.Agents.eventServerPort)
        self.server = server

        ClaudeHookInstaller.refreshInstalledScript()
        OpencodePluginInstaller.refreshIfInstalled()

        claudeUsage.start()
        claudeTokens.start()
        claudeTranscripts.start()
        codex.start()
        opencode.start()
        plans.start()

        // Re-publish nested changes so views observing the hub refresh.
        [sessions.objectWillChange, claudeUsage.objectWillChange, claudeTokens.objectWillChange, codex.objectWillChange, opencode.objectWillChange, plans.objectWillChange]
            .forEach { publisher in
                publisher.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
            }
    }

    /// Fixture entry point for snapshot rendering.
    func preview(warning: Warning?, hooksInstalled: Bool) {
        self.warning = warning
        self.hooksInstalled = hooksInstalled
    }

    func installHooks() {
        do {
            try ClaudeHookInstaller.install()
            hookError = nil
        } catch {
            hookError = error.localizedDescription
        }
        withAnimation(Motion.state) { hooksInstalled = ClaudeHookInstaller.isInstalled }
    }

    func uninstallHooks() {
        do {
            try ClaudeHookInstaller.uninstall()
            hookError = nil
        } catch {
            hookError = error.localizedDescription
        }
        withAnimation(Motion.state) { hooksInstalled = ClaudeHookInstaller.isInstalled }
    }

    func installOpencodePlugin() {
        do {
            try OpencodePluginInstaller.install()
            opencodePluginError = nil
        } catch {
            opencodePluginError = error.localizedDescription
        }
        withAnimation(Motion.state) { opencodePluginInstalled = OpencodePluginInstaller.isInstalled }
    }

    func uninstallOpencodePlugin() {
        do {
            try OpencodePluginInstaller.uninstall()
            opencodePluginError = nil
        } catch {
            opencodePluginError = error.localizedDescription
        }
        withAnimation(Motion.state) { opencodePluginInstalled = OpencodePluginInstaller.isInstalled }
    }

    func usage(for provider: AgentProvider) -> ProviderUsage {
        switch provider {
        case .claude: claudeUsage.usage
        case .codex: codex.usage
        case .opencode: opencodeUsageWithGoLimits
        }
    }

    /// opencode's own store has no limits; an OpenCode Go subscription adds its bars to the same block.
    private var opencodeUsageWithGoLimits: ProviderUsage {
        var usage = opencode.usage
        guard let go = plans.openCodeGo, !go.windows.isEmpty else { return usage }
        usage.windows = go.windows
        // The bars come from the Go account, so they carry its fetch time, not the local DB's.
        usage.updatedAt = go.updatedAt ?? usage.updatedAt
        if usage.state != .ready { usage.state = go.state }
        return usage
    }

    func tokens(for provider: AgentProvider) -> TokenTally {
        switch provider {
        case .claude: claudeTokens.tokens
        case .codex: codex.tokens
        case .opencode: opencode.tokens
        }
    }
}

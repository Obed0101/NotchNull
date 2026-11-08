import AppKit
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
    @Published private(set) var installed: Set<AgentProvider>
    @Published private(set) var hooksInstalled = !Motion.isSnapshot && ClaudeHookInstaller.isInstalled
    @Published private(set) var hookError: String?
    @Published private(set) var opencodePluginInstalled = !Motion.isSnapshot && OpencodePluginInstaller.isInstalled
    @Published private(set) var opencodePluginError: String?

    private var server: AgentEventServer?
    let usageHistory = UsageHistoryStore()
    private var cancellables: Set<AnyCancellable> = []
    private let installation: AgentInstallation
    private var activationThrottle = AgentAvailabilityRefreshThrottle()

    init(installation: AgentInstallation? = nil) {
        let resolvedInstallation = installation ?? (Motion.isSnapshot
            ? AgentInstallation(homeDirectory: FileManager.default.temporaryDirectory)
            : .live())
        self.installation = resolvedInstallation
        installed = Motion.isSnapshot ? [] : resolvedInstallation.installedProviders()
        codex = CodexMonitor(store: sessions)
        opencode = OpencodeMonitor(store: sessions)
    }

    func refreshInstalled() {
        let next = installation.installedProviders()
        guard next != installed else { return }
        withAnimation(Motion.state) { installed = next }
    }

    func start() {
        refreshAfterAppActivation()
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshAfterAppActivation() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.opencode.refreshNow() }
            .store(in: &cancellables)

        // Observe source publications even while the panel is closed; never poll providers again.
        let prefs = Preferences.shared
        prefs.$claudeUsageEnabled.combineLatest(prefs.$codexEnabled, prefs.$opencodeEnabled, prefs.$planUsageEnabled)
            .sink { [weak self] claude, codex, opencode, plans in
                self?.usageHistory.setActive(claude || codex || opencode || plans)
            }.store(in: &cancellables)
        claudeUsage.$usage.combineLatest(prefs.$claudeUsageEnabled)
            .merge(with: codex.$usage.combineLatest(prefs.$codexEnabled),
                   opencode.$usage.combineLatest(prefs.$opencodeEnabled))
            .sink { [weak self] usage, enabled in
                guard enabled else {
                    self?.usageHistory.interrupt(provider: usage.provider.rawValue)
                    return
                }
                self?.usageHistory.record(provider: usage.provider.rawValue, plan: usage.plan,
                    windows: usage.windows, updatedAt: usage.updatedAt, state: usage.state)
            }.store(in: &cancellables)
        prefs.$opencodeAccountUsageAllowed.removeDuplicates().dropFirst()
            .sink { [weak self] _ in self?.usageHistory.interruptMissingPlans(present: []) }
            .store(in: &cancellables)
        plans.$usages.combineLatest(prefs.$planUsageEnabled)
            .sink { [weak self] usages, enabled in
            let usages = enabled ? usages : []
            self?.usageHistory.interruptMissingPlans(present: Set(usages.map(\.id)))
            for usage in usages {
                self?.usageHistory.record(provider: usage.id, plan: usage.plan,
                    windows: usage.windows, updatedAt: usage.updatedAt, state: usage.state)
            }
        }.store(in: &cancellables)
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
        let server = AgentEventServer(token: ClaudeHookInstaller.token()) { [weak self] request in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, Preferences.shared.agentsEnabled else { return }
                    if request.path == "/opencode" {
                        opencodeHandler.handle(request)
                        self.opencode.refreshNow()
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
    func preview(warning: Warning?, hooksInstalled: Bool, opencodePluginInstalled: Bool, installed: Set<AgentProvider>) {
        self.warning = warning
        self.hooksInstalled = hooksInstalled
        self.opencodePluginInstalled = opencodePluginInstalled
        self.installed = installed
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

    func refreshAfterAppActivation(at date: Date = Date()) {
        // Session state is cheap and should not wait for the installation throttle.
        opencode.refreshNow()
        guard activationThrottle.shouldRefresh(at: date) else { return }
        refreshInstalled()
    }

    /// Installation and local sessions do not establish a paid Go subscription.
    var showsOpenCodeUsage: Bool {
        Preferences.shared.opencodeEnabled && !(plans.openCodeGo?.windows.isEmpty ?? true)
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

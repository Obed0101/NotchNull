import Combine
import Foundation
import SwiftUI

/// Limits of every other coding subscription found on this Mac (see `PlanProviders`). Providers
/// without a key are never contacted; a key on an account without that plan hides the provider.
@MainActor
final class PlanUsageService: ObservableObject {
    /// Subscriptions with a key, in registry order; those without a plan are left out.
    @Published private(set) var usages: [PlanUsage] = []
    /// Why the active OpenCode Console account could (not) be used, for Settings. Nil when the
    /// export path is off (legacy behavior) or before the first refresh.
    @Published private(set) var openCodeAccount: OpenCodeAuthExport.Selection?

    private var timer: Timer?
    private var inFlight = false
    private var warnedWindows: Set<String> = []
    private var cancellables: Set<AnyCancellable> = []
    var onWarning: ((String, UsageWindow) -> Void)?

    func start() {
        Preferences.shared.$planUsageEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in enabled ? self?.resume() : self?.pause() }
            .store(in: &cancellables)
        // Turning the OpenCode account consent on resolves it now instead of at the next tick.
        Preferences.shared.$opencodeAccountUsageAllowed
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard Preferences.shared.planUsageEnabled else { return }
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    /// OpenCode Go's limits, which the opencode agent block shows when opencode is watched.
    var openCodeGo: PlanUsage? { usages.first { $0.id == OpenCodeGoPlan.planID } }

    /// Fixture entry point for snapshot rendering.
    func preview(_ usages: [PlanUsage], openCodeAccount: OpenCodeAuthExport.Selection? = nil) {
        self.usages = usages
        self.openCodeAccount = openCodeAccount
    }

    private func resume() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Constants.Agents.planUsageInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    private func pause() {
        timer?.invalidate()
        timer = nil
        withAnimation(Motion.state) {
            usages = []
            openCodeAccount = nil
        }
    }

    func refresh() {
        guard !inFlight else { return }
        inFlight = true
        // Reading the active account is a separate consent on top of plan usage; without it the
        // export is never run and only the legacy environment/auth.json keys are used.
        let accountUsageAllowed = Preferences.shared.opencodeAccountUsageAllowed
        Task {
            defer { inFlight = false }
            let (found, account) = await Task.detached(priority: .utility) { () -> ([(any PlanProvider, PlanCredential)], OpenCodeAuthExport.Selection?) in
                let sources = PlanCredentialSources.load(accountUsageAllowed: accountUsageAllowed)
                let credentials = PlanProviders.all.compactMap { provider in provider.credential(in: sources).map { (provider, $0) } }
                return (credentials, sources.openCodeAccount)
            }.value
            if openCodeAccount != account { openCodeAccount = account }
            let results = await withTaskGroup(of: (Int, Result<PlanSnapshot, PlanError>).self) { group in
                for (index, (provider, credential)) in found.enumerated() {
                    group.addTask {
                        do { return (index, .success(try await provider.fetch(credential))) }
                        catch let error as PlanError { return (index, .failure(error)) }
                        catch { return (index, .failure(.unavailable(error.localizedDescription))) }
                    }
                }
                var collected: [Int: Result<PlanSnapshot, PlanError>] = [:]
                for await (index, result) in group { collected[index] = result }
                return collected
            }
            apply(found.enumerated().compactMap { index, pair in results[index].map { (pair.0, pair.1, $0) } })
        }
    }

    func apply(_ results: [(provider: any PlanProvider, credential: PlanCredential, result: Result<PlanSnapshot, PlanError>)]) {
        let now = Date()
        var next: [PlanUsage] = []
        for (provider, credential, result) in results {
            let previous = usages.first { $0.id == provider.id }
            var usage = PlanUsage(id: provider.id, title: provider.title, monogram: provider.monogram, tint: provider.tint, source: credential.source)
            switch result {
            case .success(let snapshot):
                usage.plan = snapshot.plan
                usage.windows = snapshot.windows
                usage.updatedAt = now
                usage.state = .ready
                warn(provider.title, snapshot.windows)
            case .failure(.noSubscription):
                continue
            case .failure(.signedOut(let message)):
                if provider.id == OpenCodeGoPlan.planID, previous?.updatedAt == nil { continue }
                usage.state = .signedOut(message)
            case .failure(.unavailable(let message)):
                // Finding a generic OpenCode key is not evidence of a paid Go subscription.
                if provider.id == OpenCodeGoPlan.planID, previous?.updatedAt == nil { continue }
                // Keep the last good numbers through a failed refresh.
                usage.plan = previous?.plan
                usage.windows = previous?.windows ?? []
                usage.updatedAt = previous?.updatedAt
                usage.state = .unavailable(message)
                Log.agents.notice("\(provider.title, privacy: .public) usage unavailable: \(message, privacy: .public)")
            }
            next.append(usage)
        }
        if next != usages { withAnimation(Motion.state) { usages = next } }
    }

    private func warn(_ provider: String, _ windows: [UsageWindow]) {
        for window in windows where window.severity != .normal {
            guard warnedWindows.insert(window.warningKey(provider: provider)).inserted else { continue }
            onWarning?(provider, window)
        }
    }
}

import SwiftUI

struct AgentsTab: View {
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var plans: PlanUsageService

    /// Plans shown as their own block; OpenCode Go's bars join the opencode block instead.
    private var separatePlans: [PlanUsage] {
        plans.usages.filter { !(preferences.opencodeEnabled && $0.id == OpenCodeGoPlan.planID && !$0.windows.isEmpty) }
    }

    var body: some View {
        HStack(spacing: 10) {
            Card(padding: 8) {
                NotchScroll {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        VStack(alignment: .leading, spacing: 6) {
                            if preferences.claudeUsageEnabled {
                                ProviderUsageBlock(provider: .claude)
                                    .condense(delay: Motion.stagger(1))
                            }
                            if preferences.claudeUsageEnabled && preferences.codexEnabled {
                                Rectangle().fill(Theme.Palette.hairline).frame(height: 1)
                            }
                            if preferences.codexEnabled {
                                ProviderUsageBlock(provider: .codex)
                                    .condense(delay: Motion.stagger(2))
                            }
                            if preferences.opencodeEnabled && (preferences.claudeUsageEnabled || preferences.codexEnabled) {
                                Rectangle().fill(Theme.Palette.hairline).frame(height: 1)
                            }
                            if preferences.opencodeEnabled {
                                ProviderUsageBlock(provider: .opencode)
                                    .condense(delay: Motion.stagger(3))
                            }
                            ForEach(Array(separatePlans.enumerated()), id: \.element.id) { index, usage in
                                if index > 0 || preferences.claudeUsageEnabled || preferences.codexEnabled || preferences.opencodeEnabled {
                                    Rectangle().fill(Theme.Palette.hairline).frame(height: 1)
                                }
                                PlanUsageBlock(usage: usage)
                                    .condense(delay: Motion.stagger(3 + index))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            SessionsCard()
                .frame(width: preferences.panelWidth < 640 ? 172 : 240)
                .condense(delay: Motion.stagger(3))
        }
    }
}

private struct ProviderUsageBlock: View {
    let provider: AgentProvider
    @EnvironmentObject private var agents: AgentHub
    @EnvironmentObject private var sessions: AgentSessionStore
    @EnvironmentObject private var preferences: Preferences
    private var compact: Bool { preferences.panelWidth < 640 }

    var body: some View {
        let usage = agents.usage(for: provider)
        let tokens = agents.tokens(for: provider)
        let isRunning = sessions.running.contains { $0.provider == provider }
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                ProviderMark(provider: provider, animating: isRunning, size: 14)
                Text(provider.title)
                    .font(Theme.Typeface.title)
                    .foregroundStyle(Theme.Palette.textPrimary)
                if let plan = usage.plan {
                    Text(plan)
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(provider.tint)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(provider.tint.opacity(0.16)))
                }
                Spacer(minLength: 4)
                if tokens.today > 0 {
                    if !compact {
                        HourlyBars(values: tokens.hourly, tint: provider.tint, highlight: Calendar.current.component(.hour, from: Date()))
                            .frame(width: 58, height: 12)
                    }
                    HStack(spacing: 3) {
                        Text(Formatting.tokens(tokens.today))
                            .font(Theme.Typeface.metric)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .contentTransition(.numericText(value: Double(tokens.today)))
                        Text("today")
                            .font(Theme.Typeface.caption)
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                    .help("\(tokens.today.formatted()) tokens today (input, output and cache) across \(tokens.messages.formatted()) responses; \(Formatting.tokens(tokens.output)) output tokens.")
                }
            }
            switch usage.state {
            case .loading:
                ShimmerLine().frame(height: 14)
            case .signedOut(let message), .unavailable(let message):
                if provider == .claude && !preferences.keychainAllowed {
                    HStack(spacing: 6) {
                        Text("Limits need Claude Code's sign-in")
                            .font(Theme.Typeface.caption)
                            .foregroundStyle(Theme.Palette.textTertiary)
                            .lineLimit(1)
                        Chip(title: "Allow", tint: provider.tint) { preferences.keychainAllowed = true }
                            .help(ClaudeUsageService.keychainConsentMessage)
                    }
                } else if usage.windows.isEmpty {
                    Text(message)
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                } else {
                    windows(usage)
                    Text(message)
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.Accent.warning)
                }
            case .ready:
                windows(usage)
            }
        }
    }

    @ViewBuilder
    private func windows(_ usage: ProviderUsage) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 2) {
                ForEach(usage.windows) { window in
                    UsageWindowRow(window: window, tint: provider.tint, now: context.date, breakdown: window.label == "Week" ? usage.breakdown : [])
                }
            }
            .help(provider == .codex ? "From Codex logs, updated \(usage.updatedAt.map { Formatting.relative($0, now: context.date) } ?? "—")" : provider == .opencode ? "From the local opencode database, updated \(usage.updatedAt.map { Formatting.relative($0, now: context.date) } ?? "—")" : "")
        }
    }
}

/// Another coding subscription: its tile, name and plan, then the same limit rows as Claude and Codex.
private struct PlanUsageBlock: View {
    let usage: PlanUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                PlanMonogram(text: usage.monogram, tint: usage.tint, size: 14)
                Text(usage.title)
                    .font(Theme.Typeface.title)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                if let plan = usage.plan {
                    Text(plan)
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(usage.tint)
                        .padding(.horizontal, 6)
                        .frame(height: 16)
                        .background(Capsule().fill(usage.tint.opacity(0.16)))
                }
                Spacer(minLength: 4)
            }
            switch usage.state {
            case .loading:
                ShimmerLine().frame(height: 14)
            case .signedOut(let message), .unavailable(let message):
                if !usage.windows.isEmpty { windows }
                Text(message)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(usage.windows.isEmpty ? Theme.Palette.textTertiary : Theme.Accent.warning)
            case .ready:
                windows
            }
        }
    }

    private var windows: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 2) {
                ForEach(usage.windows) { window in
                    UsageWindowRow(window: window, tint: usage.tint, now: context.date)
                }
            }
            .help("Key from \(usage.source), updated \(usage.updatedAt.map { Formatting.relative($0, now: context.date) } ?? "—")")
        }
    }
}

/// A rounded tile with the provider's initials in its tint, standing in for a logo.
struct PlanMonogram: View {
    let text: String
    let tint: Color
    var size: CGFloat = 14

    var body: some View {
        Text(text)
            .font(.system(size: size * (text.count > 1 ? 0.5 : 0.62), weight: .heavy, design: .rounded))
            .foregroundStyle(.black)
            .minimumScaleFactor(0.5)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(tint))
            .accessibilityHidden(true)
    }
}

private struct UsageWindowRow: View {
    let window: UsageWindow
    let tint: Color
    let now: Date
    var breakdown: [UsageShare] = []
    @EnvironmentObject private var preferences: Preferences
    private var showPace: Bool { preferences.paceWarnings }
    private var compact: Bool { preferences.panelWidth < 640 }

    var body: some View {
        let color: Color = switch window.severity {
        case .critical: Theme.Accent.danger
        case .warning: Theme.Accent.warning
        case .normal: tint
        }
        // Remaining mode reads like a battery: the bar empties as you use it, and the tick
        // marks how much time is left, so a fill shorter than the tick means you are over pace.
        let remaining = preferences.usageShowsRemaining
        // What is left rounds down, so "100% left" only appears before anything is used.
        let shown = remaining ? (100 - window.percent).rounded(.down) : window.percent.rounded()
        let elapsed = window.elapsedFraction(at: now)
        let exhaustion = showPace ? window.projectedExhaustion(at: now) : nil
        HStack(spacing: 6) {
            Text(window.label)
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: 40, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            UsageBar(percent: shown, tint: color, paceFraction: remaining ? elapsed.map { 1 - $0 } : elapsed, height: preferences.panelHeight >= 176 ? 8 : 6)
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(shown))%")
                    .font(Theme.Typeface.metric)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .contentTransition(.numericText(value: shown))
                Text(remaining ? "left" : "used")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            .fixedSize()
            .frame(width: 52, alignment: .leading)
            timeColumn(exhaustion: exhaustion)
                .frame(width: compact ? 60 : 74, alignment: .trailing)
        }
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// Reset time, or — when the current pace empties the window first — when it runs out, in amber.
    @ViewBuilder
    private func timeColumn(exhaustion: Date?) -> some View {
        if let exhaustion {
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8, weight: .bold))
                Text(Formatting.resetTime(exhaustion, now: now))
                    .font(Theme.Typeface.caption.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Theme.Accent.warning)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        } else {
            Text(window.resetsAt.map { Formatting.resetTime($0, now: now) } ?? "—")
                .font(Theme.Typeface.caption.monospacedDigit())
                .foregroundStyle(Theme.Palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .transition(.opacity)
        }
    }

    private var accessibilityText: String {
        var text = "\(window.label) limit \(Int(100 - window.percent)) percent left"
        if showPace, let exhaustion = window.projectedExhaustion(at: now) {
            text += ", runs out \(Formatting.moment(exhaustion, now: now)) at the current pace"
        }
        return text
    }

    private var helpText: String {
        var lines = ["\(window.label): \(Int(100 - window.percent))% left (\(Int(window.percent))% used)"]
        if let reset = window.resetsAt { lines.append("Resets \(reset.formatted(date: .abbreviated, time: .shortened))") }
        if let rates = window.rates(at: now) {
            let unit = rates.unit >= 86_400 ? "day" : "hour"
            lines.append("Pace: \(Formatting.percent(rates.used)) per \(unit) so far; \(Formatting.percent(rates.budget)) per \(unit) lasts until the reset.")
            if let exhaustion = window.projectedExhaustion(at: now) {
                lines.append("At this pace it runs out \(Formatting.moment(exhaustion, now: now)), before it resets.")
            }
        }
        if !breakdown.isEmpty {
            lines.append(breakdown.filter { $0.percent > 0 }.map { "\($0.label) \(Int($0.percent))%" }.joined(separator: " · "))
        }
        lines.append("The white tick marks how much time is left in the window.")
        return lines.joined(separator: "\n")
    }
}

private struct SessionsCard: View {
    @EnvironmentObject private var sessions: AgentSessionStore
    @EnvironmentObject private var agents: AgentHub

    var body: some View {
        Card(padding: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Sessions")
                        .font(Theme.Typeface.label)
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Spacer()
                    if !sessions.running.isEmpty {
                        Text("\(sessions.running.count) running")
                            .font(Theme.Typeface.caption)
                            .foregroundStyle(Theme.Accent.claude)
                            .contentTransition(.numericText(value: Double(sessions.running.count)))
                    }
                }
                .padding(.horizontal, 4)
                if sessions.sessions.isEmpty {
                    emptyState
                } else {
                    NotchScroll {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            VStack(spacing: 2) {
                                ForEach(Array(sessions.ordered.prefix(12).enumerated()), id: \.element.id) { index, session in
                                    SessionRow(session: session)
                                        .condense(delay: Motion.stagger(index + 3))
                                        .transition(.notchContent)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    ApprovalAlertsPrompt()
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)
            Text("No live sessions")
                .font(Theme.Typeface.bodyStrong)
                .foregroundStyle(Theme.Palette.textSecondary)
            Text("Claude Code, Codex and opencode runs on this Mac appear here automatically while they work.")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            ApprovalAlertsPrompt()
        }
        .padding(.horizontal, 4)
    }
}

/// One-line offer to add the Claude Code hooks that make approval requests instant.
private struct ApprovalAlertsPrompt: View {
    @EnvironmentObject private var agents: AgentHub

    var body: some View {
        if !agents.hooksInstalled {
            HStack(spacing: 6) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.Accent.needsYou)
                Text(agents.hookError ?? "Approval alerts")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(agents.hookError == nil ? Theme.Palette.textSecondary : Theme.Accent.danger)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Chip(title: "Enable", tint: Theme.Accent.claude) { agents.installHooks() }
                    .help("Adds a small hook to ~/.claude/settings.json (your hooks stay; a backup is saved) so the notch lights up the moment Claude asks for permission.")
            }
            .padding(.horizontal, 4)
            .transition(.opacity)
        }
    }
}

private struct SessionRow: View {
    let session: AgentSession
    @EnvironmentObject private var sessions: AgentSessionStore

    var body: some View {
        Button {
            if TerminalJumper.canJump(to: session) { TerminalJumper.jump(to: session) }
        } label: {
            HStack(spacing: 8) {
                ProviderMark(provider: session.provider, animating: session.status == .running, size: 13)
                VStack(alignment: .leading, spacing: 0) {
                    Text(session.project)
                        .font(Theme.Typeface.bodyStrong)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(subtitleColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 4)
                trailing
            }
            .padding(.horizontal, 4)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(cornerRadius: 10, padding: EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 2)))
        .help(TerminalJumper.canJump(to: session) ? "Jump to this session's terminal" : session.cwd)
    }

    private var subtitle: String {
        switch session.status {
        case .needsYou(let message): message
        case .running: session.detail ?? "Working…"
        case .done: session.detail ?? "Finished"
        case .idle: session.origin.map { "Idle · \($0)" } ?? "Idle"
        }
    }

    private var subtitleColor: Color {
        session.needsAttention ? Theme.Accent.needsYou : Theme.Palette.textTertiary
    }

    @ViewBuilder
    private var trailing: some View {
        switch session.status {
        case .needsYou:
            Circle().fill(Theme.Accent.needsYou).frame(width: 7, height: 7).modifier(PulseDot())
        case .running:
            if let start = session.turnStartedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Formatting.elapsed(context.date.timeIntervalSince(start)))
                        .font(Theme.Typeface.caption.monospacedDigit())
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.Accent.success)
        case .idle:
            // opencode's DB cannot say when a chat was last touched
            // (views/syncs bump it; titling rewrites it), so a relative time
            // here is fiction. Static "Idle" for opencode only.
            if session.provider == .opencode {
                Text("Idle")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            } else {
                Text(Formatting.relative(session.updatedAt))
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }
}

/// Loading placeholder that sweeps a highlight.
struct ShimmerLine: View {
    var body: some View {
        IndeterminateSweep(tint: Color.white.opacity(0.35))
            .background(Capsule().fill(Theme.Palette.surface))
            .clipShape(Capsule())
    }
}

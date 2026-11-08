import SwiftUI

struct AgentsTab: View {
    @EnvironmentObject private var agents: AgentHub
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var plans: PlanUsageService
    @EnvironmentObject private var model: NotchViewModel
    @State private var usageConsumer = UUID()

    private var visibleProviders: [AgentProvider] {
        AgentProvider.visible(
            installed: agents.installed,
            enabled: [
                .claude: preferences.claudeUsageEnabled,
                .codex: preferences.codexEnabled,
                // Installation and local sessions do not establish a paid Go subscription.
                .opencode: agents.showsOpenCodeUsage,
            ]
        )
    }

    private var showsOpencodeBlock: Bool { visibleProviders.contains(.opencode) }

    /// Plans shown as their own block; OpenCode Go's bars join the opencode block instead.
    private var separatePlans: [PlanUsage] {
        plans.usages.filter { !(showsOpencodeBlock && $0.id == OpenCodeGoPlan.planID && !$0.windows.isEmpty) }
    }

    private var usageEntries: [UsageEntry] {
        visibleProviders.map(UsageEntry.provider) + separatePlans.map(UsageEntry.plan)
    }

    var body: some View {
        HStack(spacing: 10) {
            Card(padding: 8) {
                NotchScroll {
                    VStack(alignment: .leading, spacing: 3) {
                        if agents.installed.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(AgentAvailabilityCopy.noAgentsInstalledTitle)
                                    .font(Theme.Typeface.bodyStrong)
                                    .foregroundStyle(Theme.Palette.textSecondary)
                                Text(AgentAvailabilityCopy.noAgentsInstalledDetail)
                                    .font(Theme.Typeface.caption)
                                    .foregroundStyle(Theme.Palette.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else if usageEntries.isEmpty {
                            Text("No agent usage to show")
                                .font(Theme.Typeface.caption)
                                .foregroundStyle(Theme.Palette.textTertiary)
                        }
                        ForEach(Array(usageEntries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 || agents.installed.isEmpty {
                                Rectangle().fill(Theme.Palette.hairline).frame(height: 1)
                            }
                            usageEntry(entry, index: index)
                        }
                    }
                    .background(AgentsHeightReader(field: .provider))
                }
            }
            .frame(maxWidth: .infinity)
            SessionsCard()
                .frame(width: preferences.panelWidth < 640 ? 172 : 240)
                .condense(delay: Motion.stagger(3))
        }
        .onPreferenceChange(AgentsHeightsKey.self) { heights in
            MainActor.assumeIsolated {
                let tallest = max(heights.provider, heights.sessionColumn)
                model.requestPanelContentHeight(PanelFit.contentHeight(tallestColumn: tallest), for: .agents)
            }
        }
        .onAppear {
            guard !Motion.isSnapshot else { return }
            agents.refreshInstalled()
            agents.opencode.setUsageVisible(showsOpencodeBlock, consumer: usageConsumer)
        }
        // Today's opencode messages are read only while its block is on screen.
        .onChange(of: showsOpencodeBlock) { _, shown in
            guard !Motion.isSnapshot else { return }
            agents.opencode.setUsageVisible(shown, consumer: usageConsumer)
        }
        .onDisappear {
            guard !Motion.isSnapshot else { return }
            agents.opencode.setUsageVisible(false, consumer: usageConsumer)
        }
    }

    @ViewBuilder
    private func usageEntry(_ entry: UsageEntry, index: Int) -> some View {
        switch entry {
        case .provider(let provider):
            ProviderUsageBlock(provider: provider)
                .condense(delay: Motion.stagger(index + 1))
        case .plan(let usage):
            PlanUsageBlock(usage: usage)
                .condense(delay: Motion.stagger(index + 3))
        }
    }
}

private enum UsageEntry: Identifiable {
    case provider(AgentProvider)
    case plan(PlanUsage)

    var id: String {
        switch self {
        case .provider(let provider): "provider-\(provider.id)"
        case .plan(let usage): "plan-\(usage.id)"
        }
    }
}

/// Natural heights of the two Agents columns. Every probe writes one field and `reduce` merges the
/// maxima, so the tab can request one fitted height without measuring the stretched cards.
private struct AgentsHeights: Equatable {
    enum Field {
        case provider, sessionHeader, sessionRows, sessionEmpty, approvalPrompt
    }

    static let spacing: CGFloat = 4

    var provider: CGFloat = 0
    var sessionHeader: CGFloat = 0
    var sessionRows: CGFloat = 0
    var sessionEmpty: CGFloat = 0
    var approvalPrompt: CGFloat = 0

    init() {}

    init(field: Field, height: CGFloat) {
        switch field {
        case .provider: provider = height
        case .sessionHeader: sessionHeader = height
        case .sessionRows: sessionRows = height
        case .sessionEmpty: sessionEmpty = height
        case .approvalPrompt: approvalPrompt = height
        }
    }

    var sessionColumn: CGFloat {
        var height = sessionHeader
        let body = sessionEmpty > 0 ? sessionEmpty : sessionRows
        if body > 0 { height += Self.spacing + body }
        if approvalPrompt > 0 { height += Self.spacing + approvalPrompt }
        return height
    }
}

private struct AgentsHeightsKey: PreferenceKey {
    static let defaultValue = AgentsHeights()

    static func reduce(value: inout AgentsHeights, nextValue: () -> AgentsHeights) {
        let next = nextValue()
        value.provider = max(value.provider, next.provider)
        value.sessionHeader = max(value.sessionHeader, next.sessionHeader)
        value.sessionRows = max(value.sessionRows, next.sessionRows)
        value.sessionEmpty = max(value.sessionEmpty, next.sessionEmpty)
        value.approvalPrompt = max(value.approvalPrompt, next.approvalPrompt)
    }
}

private struct AgentsHeightReader: View {
    let field: AgentsHeights.Field

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: AgentsHeightsKey.self,
                value: AgentsHeights(field: field, height: proxy.size.height)
            )
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
        VStack(alignment: .leading, spacing: 2) {
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
        // An opencode block with windows is showing OpenCode Go's server limits, not local tokens.
        let isGo = provider == .opencode && !usage.windows.isEmpty
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 2) {
                ForEach(usage.windows) { window in
                    UsageWindowRow(window: window, tint: provider.tint, now: context.date,
                        updatedAt: provider == .opencode ? agents.plans.openCodeGo?.updatedAt : usage.updatedAt,
                        isReady: isGo ? agents.plans.openCodeGo?.state == .ready : usage.state == .ready,
                        forecast: agents.usageHistory.forecast(provider: provider == .opencode ? OpenCodeGoPlan.planID : provider.rawValue,
                            plan: provider == .opencode ? agents.plans.openCodeGo?.plan : usage.plan, window: window, at: context.date),
                        breakdown: window.label == "Week" ? usage.breakdown : [],
                        days: agents.usageHistory.days(provider: provider == .opencode ? OpenCodeGoPlan.planID : provider.rawValue,
                            plan: provider == .opencode ? agents.plans.openCodeGo?.plan : usage.plan, window: window),
                        showsRemaining: isGo ? preferences.planUsageShowsRemaining : nil)
                }
            }
            .help(windowsHelp(usage, isGo: isGo, now: context.date))
        }
    }

    private func windowsHelp(_ usage: ProviderUsage, isGo: Bool, now: Date) -> String {
        let stamp = usage.updatedAt.map { Formatting.relative($0, now: now) } ?? "—"
        switch provider {
        case .codex: return "From Codex logs, updated \(stamp)"
        case .opencode: return isGo ? "From your OpenCode Go account, updated \(stamp)" : "From the local opencode database, updated \(stamp)"
        case .claude: return ""
        }
    }
}

/// Another coding subscription: its tile, name and plan, then the same limit rows as Claude and Codex.
private struct PlanUsageBlock: View {
    let usage: PlanUsage
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var agents: AgentHub

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
                    UsageWindowRow(window: window, tint: usage.tint, now: context.date,
                        updatedAt: usage.updatedAt, isReady: usage.state == .ready,
                        forecast: agents.usageHistory.forecast(provider: usage.id, plan: usage.plan, window: window, at: context.date),
                        days: agents.usageHistory.days(provider: usage.id, plan: usage.plan, window: window),
                        showsRemaining: preferences.planUsageShowsRemaining)
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
    let updatedAt: Date?
    let isReady: Bool
    let forecast: UsageForecast?
    var breakdown: [UsageShare] = []
    var days: [CycleDay] = []
    /// Overrides the global reading for "Other plans" rows: nil uses the Claude Code setting.
    var showsRemaining: Bool? = nil
    @EnvironmentObject private var preferences: Preferences
    private var showPace: Bool { preferences.paceWarnings }
    private var fresh: Bool {
        isReady && updatedAt.map { now.timeIntervalSince($0) >= 0 && now.timeIntervalSince($0) <= 1200 } == true
    }
    private var budget: Double? { fresh ? window.dailyBudget(at: now) : nil }
    private var estimate: UsageForecast? { fresh && showPace ? forecast : nil }
    private var forecastText: String {
        if !fresh { return "Last known usage · waiting for update" }
        if let reset = window.resetsAt, reset <= now { return "Reset passed · waiting for update" }
        if window.percent >= 100 { return "Limit reached · waiting for reset" }
        if let estimate {
            if let exhaustion = estimate.exhaustion {
                return "Est. runs out \(Formatting.resetTime(exhaustion, now: now))"
            }
            return "Est. lasts until reset"
        }
        return "Learning your hours"
    }

    var body: some View {
        let color: Color = switch window.severity {
        case .critical: Theme.Accent.danger
        case .warning: Theme.Accent.warning
        case .normal: tint
        }
        let remaining = showsRemaining ?? preferences.usageShowsRemaining
        let shown = remaining ? (100 - window.percent).rounded(.down) : window.percent.rounded()
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(window.label).foregroundStyle(Theme.Palette.textSecondary)
                Text("\(Int(shown))% \(remaining ? "left" : "used")")
                    .font(Theme.Typeface.metric).foregroundStyle(Theme.Palette.textPrimary)
                Spacer(minLength: 0)
                Text(window.resetsAt.map { "Resets \(Formatting.resetTime($0, now: now))" } ?? "Reset unknown")
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let pace = window.dayPace(at: now) {
                // Day 1 starts at zero, so it never needs a recorded baseline.
                let today = fresh ? days.last { $0.day == pace.day } ?? (pace.day == 0 ? CycleDay(day: 0,
                    start: pace.dayStart, since: pace.dayStart, baseline: 0, latest: window.percent,
                    allowance: 100 / Double(pace.days)) : nil) : nil
                DayPaceBar(pace: pace, days: days.contains { $0.day == pace.day } ? days : days + (today.map { [$0] } ?? []), percent: window.percent, tint: color, live: fresh)
                if fresh {
                    HStack(spacing: 6) {
                        Text(today.map { Self.todayText($0, now: now) } ?? "Today · from the next reading")
                            .foregroundStyle(today?.over == true ? Theme.Accent.warning : Theme.Palette.textPrimary)
                        Spacer(minLength: 4)
                        if showPace {
                            Text(forecastText)
                                .foregroundStyle(estimate?.exhaustion == nil ? Theme.Palette.textSecondary : Theme.Accent.warning)
                        } else {
                            Text("until \(Formatting.resetTime(pace.dayEnd, now: now))")
                        }
                    }
                    .lineLimit(1)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.textSecondary)
                } else {
                    Text("Last known usage").foregroundStyle(Theme.Palette.textSecondary)
                }
            } else {
                UsageCellBar(percent: remaining ? 100 - window.percent : window.percent, tint: color, marker: nil)
                if (window.duration ?? 0) >= 86_400 && showPace && (estimate != nil || budget == nil || window.percent >= 100) {
                    Text(forecastText)
                        .foregroundStyle(estimate?.exhaustion == nil ? Theme.Palette.textSecondary : Theme.Accent.warning)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !fresh {
                    Text("Last known usage").foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        }
        .font(Theme.Typeface.caption)
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(helpText)
    }

    /// Today's own consumption against today's allowance, never the running weekly total.
    static func todayText(_ day: CycleDay, now: Date) -> String {
        let label = day.exact ? "Today" : "Since \(day.since.formatted(date: .omitted, time: .shortened))"
        return "\(label) \(Formatting.percent(day.used)) of \(Formatting.percent(day.allowance))"
    }

    private var helpText: String {
        var lines = ["\(window.label): \(Int(100 - window.percent))% left (\(Int(window.percent))% used)"]
        if let reset = window.resetsAt { lines.append("Resets \(reset.formatted(date: .abbreviated, time: .shortened))") }
        if let pace = window.dayPace(at: now) {
            lines.append("Each segment is one day of this \(pace.days)-day cycle. Days start at the reset time, not at midnight; today runs until \(pace.dayEnd.formatted(date: .abbreviated, time: .shortened)).")
            lines.append("A segment fills with that day's usage against that day's allowance: the quota left when the day began divided by the days left, so unused quota raises later allowances and overspending lowers them. Amber means the day went over. Earlier usage fills the past days in order from the reset; empty segments are days ahead.")
            for day in days {
                let total = day.complete == true || day.day == pace.day ? "" : " (at least; the end of this day was not observed)"
                let start = day.exact ? "" : " since \(day.since.formatted(date: .abbreviated, time: .shortened))"
                lines.append("Day \(day.day + 1)\(start): \(Formatting.percent(day.used)) of \(Formatting.percent(day.allowance))\(total)")
            }
        }
        if showPace && (window.duration ?? 0) >= 86_400 {
            lines.append(forecastText)
            if let estimate {
                lines.append("Usual consumption: \(Formatting.percent(estimate.dailyUse)) per day. Estimated from observed quota changes by local hour over the last 28 days; your habits can change.")
            } else if fresh {
                lines.append("Personalized estimates need at least three observed hours on three different dates for each hour of the day. Offline gaps are unknown, not zero usage.")
            }
        }
        if !breakdown.isEmpty {
            lines.append(breakdown.filter { $0.percent > 0 }.map { "\($0.label) \(Int($0.percent))%" }.joined(separator: " · "))
        }
        return lines.joined(separator: "\n")
    }
}

private struct SessionsCard: View {
    @EnvironmentObject private var sessions: AgentSessionStore
    @EnvironmentObject private var agents: AgentHub

    private var visibleSessions: [AgentSession] {
        sessions.ordered.filter { agents.installed.contains($0.provider) }
    }

    var body: some View {
        Card(padding: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Sessions")
                        .font(Theme.Typeface.label)
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Spacer()
                    let runningCount = visibleSessions.filter { $0.status == .running }.count
                    if runningCount > 0 {
                        Text("\(runningCount) running")
                            .font(Theme.Typeface.caption)
                            .foregroundStyle(Theme.Accent.claude)
                            .contentTransition(.numericText(value: Double(runningCount)))
                    }
                }
                .padding(.horizontal, 4)
                .background(AgentsHeightReader(field: .sessionHeader))
                if visibleSessions.isEmpty {
                    emptyState
                } else {
                    NotchScroll {
                        VStack(spacing: 2) {
                            ForEach(Array(visibleSessions.prefix(12).enumerated()), id: \.element.id) { index, session in
                                SessionRow(session: session)
                                    .condense(delay: Motion.stagger(index + 3))
                                    .transition(.notchContent)
                            }
                        }
                        .background(AgentsHeightReader(field: .sessionRows))
                    }
                }
                ApprovalAlertsPrompt()
                    .background(AgentsHeightReader(field: .approvalPrompt))
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No live sessions")
                .font(Theme.Typeface.bodyStrong)
                .foregroundStyle(Theme.Palette.textSecondary)
            Text(AgentAvailabilityCopy.sessionsEmptyDetail(installed: agents.installed))
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .background(AgentsHeightReader(field: .sessionEmpty))
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
            Circle().fill(Theme.Accent.needsYou).frame(width: 7, height: 7).modifier(PulseDot(tab: .agents))
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

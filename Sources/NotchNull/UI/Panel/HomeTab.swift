import AppKit
import SwiftUI

/// Home: the player on the left, the user's chosen quick rows on the right. Sized for the compact
/// default panel; extra room (a taller or wider panel) reveals the volume slider and larger art.
struct HomeTab: View {
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        let contentWidth = preferences.panelWidth - 2 * Theme.Radius.panelPadding
        HStack(spacing: 8) {
            if preferences.musicEnabled {
                NowPlayingCard()
                    .frame(width: min(300, max(190, contentWidth * 0.44)))
                    .condense(delay: Motion.stagger(1))
            }
            QuickRowsCard()
                .condense(delay: Motion.stagger(2))
        }
    }
}

struct NowPlayingCard: View {
    @EnvironmentObject private var nowPlaying: NowPlayingService
    @EnvironmentObject private var levels: LevelsService
    @EnvironmentObject private var preferences: Preferences

    private static let scrubberHeight: CGFloat = 12
    private static let transportHeight: CGFloat = 27
    /// Title, artist and source, one line each.
    private static let stackedTextHeight: CGFloat = 46

    var body: some View {
        Card(padding: 8) {
            if let track = nowPlaying.nowPlaying {
                GeometryReader { proxy in playing(track, in: proxy.size) }
            } else {
                empty
            }
        }
    }

    /// Three bands: the track, the scrubber, then transport and volume. The art takes the height
    /// the other two leave, so the card stays full at any panel size instead of opening gaps.
    private func playing(_ track: NowPlaying, in size: CGSize) -> some View {
        let gap: CGFloat = size.height >= 132 ? 10 : 7
        let free = size.height - Self.scrubberHeight - Self.transportHeight - 2 * gap
        // A tall card stacks the art over the text, like an album view, instead of floating a
        // small row in the middle.
        let stacked = free - Self.stackedTextHeight - gap >= size.width * 0.75
        // Beside the text the art stays the smaller part, unless there is height to spare.
        let share: CGFloat = free > size.width * 0.6 ? 0.5 : 0.38
        let art = stacked
            ? min(free - Self.stackedTextHeight - gap, size.width)
            : max(40, min(free, size.width * share))
        let artwork = ArtworkView(image: nowPlaying.artwork, size: art, cornerRadius: stacked ? 12 : 10, tint: nowPlaying.tint)
            .onTapGesture { nowPlaying.openPlayer() }
            .help("Open \(track.sourceName)")
        return VStack(alignment: .leading, spacing: gap) {
            if stacked {
                artwork.frame(maxWidth: .infinity)
                trackText(track, titleLines: 1)
                    .frame(height: Self.stackedTextHeight)
            } else {
                HStack(alignment: .center, spacing: 10) {
                    artwork
                    trackText(track, titleLines: art >= 62 ? 2 : 1)
                }
            }
            Scrubber(track: track, tint: nowPlaying.tint) { nowPlaying.seek(to: $0) }
                .frame(height: Self.scrubberHeight)
            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    IconButton(symbol: "backward.fill", size: 10, label: "Previous track") { nowPlaying.previous() }
                    IconButton(symbol: track.isPlaying ? "pause.fill" : "play.fill", size: 13, label: track.isPlaying ? "Pause" : "Play") {
                        nowPlaying.togglePlayPause()
                    }
                    IconButton(symbol: "forward.fill", size: 10, label: "Next track") { nowPlaying.next() }
                }
                // The glyphs, not their hover areas, line up with the art's leading edge.
                .padding(.leading, -6)
                LevelSlider(value: Double(levels.outputVolume), tint: nowPlaying.tint, label: "Output volume") {
                    levels.setVolume(Float($0))
                }
            }
            .frame(height: Self.transportHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func trackText(_ track: NowPlaying, titleLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(track.title)
                .font(Theme.Typeface.title)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(titleLines)
                .contentTransition(.opacity)
            if !track.artist.isEmpty {
                Text(track.artist)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
            }
            HStack(spacing: 5) {
                if track.isPlaying {
                    AudioBars(isPlaying: true, tint: nowPlaying.tint, barCount: 4, barWidth: 2, spacing: 1.6, height: 9)
                        .transition(.opacity)
                }
                Text(track.sourceName)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
            }
            .animation(Motion.feedback, value: track.isPlaying)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            Image(systemName: "music.note")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text("Nothing playing")
                .font(Theme.Typeface.bodyStrong)
                .foregroundStyle(Theme.Palette.textSecondary)
            HStack(spacing: 6) {
                Chip(title: "Music") { launch("com.apple.Music") }
                Chip(title: "Spotify") { launch("com.spotify.client") }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func launch(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Track progress; hover to enlarge, click or drag to seek.
struct Scrubber: View {
    let track: NowPlaying
    let tint: Color
    let onSeek: (Double) -> Void
    @State private var hovering = false
    @State private var dragFraction: Double?

    var body: some View {
        if track.duration > 0 {
            scrubber
        } else if track.hasMetadata {
            LiveBadge(tint: tint)
        } else {
            Text("This player shares no track info")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
        }
    }

    private var scrubber: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let elapsed = track.elapsed(at: context.date)
            let fraction = dragFraction ?? (track.duration > 0 ? elapsed / track.duration : 0)
            HStack(spacing: 6) {
                Text(Formatting.clock(dragFraction.map { $0 * track.duration } ?? elapsed))
                    .font(Theme.Typeface.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.textTertiary)
                    // Sized by the text: an hour-long track never wraps into a second line.
                    .fixedSize()
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.Palette.track)
                        Capsule().fill(hovering ? tint : Color.white.opacity(0.85))
                            .frame(width: max(4, proxy.size.width * fraction))
                    }
                    .frame(height: hovering ? 6 : 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in dragFraction = max(0, min(1, value.location.x / proxy.size.width)) }
                            .onEnded { _ in
                                if let dragFraction { onSeek(dragFraction) }
                                dragFraction = nil
                            }
                    )
                }
                .frame(height: 12)
                Text("-" + Formatting.clock(max(0, track.duration - elapsed)))
                    .font(Theme.Typeface.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .fixedSize()
            }
            .animation(Motion.feedback, value: hovering)
        }
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
    }
}

/// Stands in for the scrubber when the source has no duration (live streams, some web players).
private struct LiveBadge: View {
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Circle().fill(Theme.Accent.danger).frame(width: 5, height: 5).modifier(PulseDot())
                Text("LIVE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            .padding(.horizontal, 6)
            .frame(height: 16)
            .background(Capsule().fill(Theme.Accent.danger.opacity(0.18)))
            Capsule()
                .fill(LinearGradient(colors: [tint.opacity(0.6), tint.opacity(0.15)], startPoint: .leading, endPoint: .trailing))
                .frame(height: 4)
        }
        .frame(height: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live")
    }
}

/// The quick list: rows chosen in Settings → Tabs & Wings, in their order. Built-in rows and
/// widgets that declare a `home` block share it.
struct QuickRowsCard: View {
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var stats: SystemStatsService
    @EnvironmentObject private var battery: BatteryService
    @EnvironmentObject private var widgets: WidgetStore

    var body: some View {
        Card(padding: 6) {
            let keys = keys
            if keys.isEmpty {
                Text("Choose rows in Settings › Tabs & Wings")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { proxy in
                    NotchScroll {
                        // Rows share any extra height evenly, so a taller panel spaces them out
                        // instead of leaving a gap at the bottom.
                        VStack(spacing: 0) {
                            ForEach(Array(keys.enumerated()), id: \.element) { index, key in
                                view(for: key)
                                    .frame(maxHeight: .infinity)
                                    .condense(delay: Motion.stagger(index + 2))
                            }
                        }
                    }
                    .environment(\.infoRowHeight, Self.rowHeight(count: keys.count, available: proxy.size.height))
                }
            }
        }
        .onAppear { stats.setActive(true) }
        .onDisappear { stats.setActive(false) }
    }

    /// Full-height rows while they fit; a list a few points too tall tightens before it scrolls.
    static func rowHeight(count: Int, available: CGFloat) -> CGFloat {
        CGFloat(count) * 26 <= available ? 26 : 24
    }

    private var homeWidgets: [LoadedWidget] { widgets.widgets.filter { $0.homeRow != nil } }

    private var keys: [String] {
        let shown = Set(homeWidgets.filter(\.showsHomeRow).map { Preferences.widgetRowPrefix + $0.id })
        return preferences.homeKeys(widgetRows: homeWidgets.map(\.id)).filter { key in
            guard let row = Preferences.HomeRow(rawValue: key) else { return shown.contains(key) }
            return switch row {
            case .upNext: preferences.calendarEnabled
            case .system, .network, .storage: preferences.statsEnabled
            case .agents: preferences.agentsEnabled
            case .battery: preferences.batteryEnabled && (battery.state.hasBattery || Motion.isSnapshot)
            case .clipboard: preferences.clipboardEnabled
            case .keepAwake, .timer, .toggles: true
            }
        }
    }

    @ViewBuilder
    private func view(for key: String) -> some View {
        switch Preferences.HomeRow(rawValue: key) {
        case .keepAwake: KeepAwakeRow()
        case .upNext: UpNextRow()
        case .timer: TimerRow()
        case .system: SystemRow()
        case .agents: AgentLimitsRow()
        case .network: NetworkRow()
        case .battery: BatteryRow()
        case .storage: StorageRow()
        case .toggles: TogglesRow()
        case .clipboard: ClipboardRow()
        case nil:
            if let widget = homeWidgets.first(where: { Preferences.widgetRowPrefix + $0.id == key }) {
                WidgetHomeRow(widget: widget)
            }
        }
    }
}

private struct KeepAwakeRow: View {
    @EnvironmentObject private var keepAwake: KeepAwakeService

    var body: some View {
        InfoRow(symbol: "cup.and.saucer.fill", tint: Theme.Accent.awake, title: "Keep Awake") {
            Button(keepAwake.isActive ? remainingLabel : keepAwake.duration.title) { keepAwake.cycleDuration() }
                .buttonStyle(PressableStyle(padding: EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4)))
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .lineLimit(1)
                .layoutPriority(-1)
            NotchToggle(
                isOn: Binding(get: { keepAwake.isActive }, set: { $0 ? keepAwake.start() : keepAwake.stop() }),
                tint: Theme.Accent.awake,
                label: "Keep Awake"
            )
        }
    }

    private var remainingLabel: String {
        guard let endsAt = keepAwake.endsAt else { return "On" }
        return Formatting.countdown(to: endsAt).replacingOccurrences(of: "in ", with: "")
    }
}

private struct UpNextRow: View {
    @EnvironmentObject private var calendar: CalendarService

    var body: some View {
        InfoRow(symbol: "video.fill", tint: Theme.Accent.calendar, title: "Up next") {
            switch calendar.access {
            case .fullAccess:
                if let event = calendar.next {
                    Text(event.title)
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                        .layoutPriority(-1)
                    Text(event.isOngoing ? "now" : Formatting.countdown(to: event.start).replacingOccurrences(of: "in ", with: ""))
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .fixedSize()
                    if event.meetingURL != nil {
                        Chip(title: "Join", tint: Theme.Accent.success) { calendar.join(event) }
                    }
                } else {
                    Text("Free")
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            case .notDetermined:
                Chip(title: "Connect", tint: Theme.Accent.calendar) { calendar.requestAccess() }
            default:
                Chip(title: "Allow", tint: Theme.Accent.warning) { Permissions.open(.calendars) }
            }
        }
    }
}

private struct TimerRow: View {
    @EnvironmentObject private var timer: TimerService
    @State private var showCustom = false

    var body: some View {
        InfoRow(symbol: "timer", tint: Theme.Accent.timer, title: "Timer") {
            if timer.state == .idle {
                if showCustom {
                    CustomTimerInput(
                        onCommit: { total in
                            timer.start(total)
                            withAnimation(Motion.state) { showCustom = false }
                        },
                        onCancel: {
                            withAnimation(Motion.state) { showCustom = false }
                        }
                    )
                    .transition(.notchContent)
                } else {
                    ForEach([5, 15, 25], id: \.self) { minutes in
                        Chip(title: "\(minutes)m", tint: Theme.Accent.timer) { timer.start(TimeInterval(minutes * 60)) }
                    }
                    Button {
                        withAnimation(Motion.state) { showCustom = true }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textTertiary)
                            .frame(width: 20, height: 20)
                            .background(Capsule().fill(Theme.Palette.surfaceHover))
                    }
                    .buttonStyle(PressableStyle(hoverFill: .clear, cornerRadius: 10, padding: EdgeInsets()))
                    .help("Custom timer")
                    .accessibilityLabel("Custom timer")
                }
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(TimerService.format(timer.remaining(at: context.date)))
                        .font(Theme.Typeface.metric)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(Motion.value, value: Int(timer.remaining(at: context.date)))
                }
                IconButton(symbol: timer.isRunning ? "pause.fill" : "play.fill", size: 9, label: timer.isRunning ? "Pause timer" : "Resume timer") {
                    timer.togglePause()
                }
                IconButton(symbol: "xmark", size: 9, tint: Theme.Palette.textSecondary, label: "Stop timer") { timer.cancel() }
            }
        }
        .animation(Motion.state, value: showCustom)
        .onChange(of: timer.state) { _, new in
            if new != .idle, showCustom { showCustom = false }
        }
    }
}

/// Clock-style `HH : MM : SS` editor. Tab / Shift-Tab cycles fields, typing two
/// digits auto-advances, Up/Down steps, Enter starts, Escape cancels. One-shot.
private struct CustomTimerInput: View {
    var onCommit: (TimeInterval) -> Void
    var onCancel: () -> Void

    @EnvironmentObject private var preferences: Preferences
    @State private var hr = "00"
    @State private var min = "05"
    @State private var sec = "00"
    @FocusState private var field: Field?
    @State private var showError = false

    private enum Field: Hashable { case hr, min, sec }

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 2) {
                timeField(title: "Hours", text: $hr, field: .hr)
                Text(":")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                timeField(title: "Minutes", text: $min, field: .min)
                Text(":")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                timeField(title: "Seconds", text: $sec, field: .sec)
            }
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(Theme.Palette.surfaceHover))
            .overlay {
                Capsule().strokeBorder(
                    showError ? Theme.Accent.danger : (field == nil ? .clear : Theme.Accent.timer.opacity(0.55)),
                    lineWidth: 1
                )
            }
            IconButton(symbol: "checkmark", size: 9, tint: Theme.Accent.timer, label: "Start timer") { commit() }
            IconButton(symbol: "xmark", size: 9, tint: Theme.Palette.textSecondary, label: "Cancel") { onCancel() }
        }
        .animation(Motion.feedback, value: showError)
        .onKeyPress(.tab, phases: .down) { press in
            let back = press.modifiers.contains(.shift)
            switch field {
            case .hr: field = back ? .sec : .min
            case .min: field = back ? .hr : .sec
            case .sec: field = back ? .min : .hr
            case nil: field = .hr
            }
            return .handled
        }
        .onKeyPress(.upArrow) { step(1); return .handled }
        .onKeyPress(.downArrow) { step(-1); return .handled }
        .onExitCommand { onCancel() }
        .onAppear { DispatchQueue.main.async { field = .min } }
        .onChange(of: field) { old, new in
            if old == .hr { hr = normalize(hr) }
            if old == .min { min = normalize(min) }
            if old == .sec { sec = normalize(sec) }
            if new != nil {
                // Keep the content and select it all, so typing replaces it.
                DispatchQueue.main.async {
                    (NSApp.keyWindow?.firstResponder as? NSTextView)?.selectAll(nil)
                }
            }
        }
        .onChange(of: hr) { _, new in
            let fixed = sanitize(new, for: .hr, next: .min)
            if fixed != new { hr = fixed }
        }
        .onChange(of: min) { _, new in
            let fixed = sanitize(new, for: .min, next: .sec)
            if fixed != new { min = fixed }
        }
        .onChange(of: sec) { _, new in
            let fixed = sanitize(new, for: .sec, next: nil)
            if fixed != new { sec = fixed }
        }
    }

    private func timeField(title: String, text: Binding<String>, field thisField: Field) -> some View {
        TextField("", text: text)
            .textFieldStyle(.plain)
            .font(Theme.Typeface.caption.monospacedDigit())
            .multilineTextAlignment(.center)
            .frame(width: 20)
            .foregroundStyle(Theme.Palette.textPrimary)
            .tint(preferences.accent)
            .focused($field, equals: thisField)
            .onSubmit(commit)
            .help(title)
            .accessibilityLabel("Custom timer \(title)")
    }

    /// Pads a field to two digits: "" -> "00", "1" -> "01". Runs on Tab-away
    /// and Enter so the labels always settle before focus moves or starts.
    private func normalize(_ value: String) -> String {
        let digits = value.filter(\.isNumber)
        if digits.isEmpty { return "00" }
        if digits.count == 1 { return "0" + digits }
        return String(digits.prefix(2))
    }

    /// Keeps digits only, max two chars. Extra digits keep the last two and
    /// auto-advance, mimicking the Clock app's shift behavior.
    private func sanitize(_ value: String, for thisField: Field, next: Field?) -> String {
        let digits = value.filter(\.isNumber)
        if digits.count > 2 {
            if field == thisField, let next { DispatchQueue.main.async { field = next } }
            return String(digits.suffix(2))
        }
        if digits.count == 2, field == thisField, let next {
            DispatchQueue.main.async { field = next }
        }
        return digits
    }

    private func step(_ delta: Int) {
        switch field {
        case .hr:
            let current = Int(hr) ?? 0
            hr = String(format: "%02d", (current + delta + 100) % 100)
        case .min:
            let current = Int(min) ?? 0
            min = String(format: "%02d", (current + delta + 60) % 60)
        case .sec:
            let current = Int(sec) ?? 0
            sec = String(format: "%02d", (current + delta + 60) % 60)
        case nil:
            field = .min
        }
    }

    private func commit() {
        let normalizedHr = normalize(hr)
        let normalizedMin = normalize(min)
        let normalizedSec = normalize(sec)
        hr = normalizedHr
        min = normalizedMin
        sec = normalizedSec
        let hours = Int(normalizedHr) ?? 0
        let minutes = Int(normalizedMin) ?? 0
        let seconds = Int(normalizedSec) ?? 0
        guard let total = TimerService.total(hours: hours, minutes: minutes, seconds: seconds) else {
            showError = true
            NSSound.beep()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { showError = false }
            return
        }
        onCommit(total)
    }
}

/// CPU and memory side by side in one row.
private struct SystemRow: View {
    @EnvironmentObject private var stats: SystemStatsService

    var body: some View {
        InfoRow(symbol: "cpu", tint: Theme.Accent.codex, title: "Mac") {
            MiniMeter(label: "CPU", value: stats.snapshot.cpu, tint: Theme.Accent.codex)
            MiniMeter(label: "MEM", value: stats.snapshot.memoryFraction, tint: Theme.Accent.clipboard)
        }
    }
}

private struct NetworkRow: View {
    @EnvironmentObject private var stats: SystemStatsService

    var body: some View {
        InfoRow(symbol: "arrow.up.arrow.down", tint: Theme.Accent.airdrop, title: "Network") {
            Label(Formatting.rate(stats.snapshot.downloadRate), systemImage: "arrow.down")
                .labelStyle(CompactLabel())
            Label(Formatting.rate(stats.snapshot.uploadRate), systemImage: "arrow.up")
                .labelStyle(CompactLabel())
        }
    }
}

/// Label, tiny bar and percentage for the system row.
private struct MiniMeter: View {
    let label: String
    let value: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(Theme.Palette.textTertiary)
                .fixedSize()
            UsageBar(percent: value * 100, tint: tint, height: 4)
                .frame(minWidth: 12, maxWidth: 34)
            Text("\(Int((value * 100).rounded()))%")
                .font(Theme.Typeface.caption.monospacedDigit())
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(width: 26, alignment: .trailing)
                .contentTransition(.numericText(value: value))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(Int(value * 100)) percent")
    }
}

private struct CompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon.font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
            configuration.title.font(Theme.Typeface.caption.monospacedDigit()).foregroundStyle(Theme.Palette.textPrimary)
        }
        .lineLimit(1)
    }
}

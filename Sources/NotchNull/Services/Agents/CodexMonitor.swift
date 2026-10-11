import Combine
import Foundation
import SwiftUI

/// Codex state from its rollout logs (~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl):
/// live turn status per session, the latest plan rate limits and today's token totals.
/// Codex's `notify` hook is left alone because it only supports one command.
@MainActor
final class CodexMonitor: ObservableObject {
    @Published private(set) var usage = ProviderUsage.placeholder(.codex)
    @Published private(set) var tokens = TokenTally()

    private let store: AgentSessionStore
    private nonisolated let sessionsRoot: URL
    private let queue = DispatchQueue(label: "dev.notchnull.codex", qos: .utility)
    private nonisolated(unsafe) let reader = JSONLTailReader()
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var warned: Set<String> = []
    private var limitsInFlight = false
    private var nextLimitsRefresh = Date.distantPast
    private var liveLimits: (date: Date, payload: [String: Any])?
    private let limitsQueue = DispatchQueue(label: "dev.notchnull.codex.limits", qos: .utility)
    var onWarning: ((String, UsageWindow) -> Void)?

    // Background-queue state.
    private nonisolated(unsafe) var sessionIDs: [URL: String] = [:]
    private nonisolated(unsafe) var tokenDay = Calendar.current.startOfDay(for: Date())
    private nonisolated(unsafe) var tally = TokenTally()
    private nonisolated(unsafe) var latestLimits: (date: Date, payload: [String: Any])?
    private nonisolated(unsafe) var bootstrapped = false

    init(store: AgentSessionStore, sessionsRoot: URL = Constants.Paths.codexSessions) {
        self.store = store
        self.sessionsRoot = sessionsRoot
    }

    func start() {
        Preferences.shared.$codexEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in enabled ? self?.resume() : self?.pause() }
            .store(in: &cancellables)
    }

    /// Fixture entry point for snapshot rendering.
    func preview(usage: ProviderUsage, tokens: TokenTally) {
        self.usage = usage
        self.tokens = tokens
    }

    private func resume() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Constants.Agents.codexPollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        poll()
    }

    private func pause() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        refreshAccountLimits()
        queue.async { [weak self] in
            guard let self else { return }
            let events = self.scan()
            let limits = self.latestLimits
            let tally = self.tally
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    events.forEach(self.apply)
                    guard Preferences.shared.codexEnabled else { return }
                    let current = [limits, self.liveLimits].compactMap { $0 }.max { $0.date < $1.date }
                    if let current { self.applyLimits(current.payload, at: current.date) }
                    if tally != self.tokens { withAnimation(Motion.state) { self.tokens = tally } }
                    if current == nil, self.usage.state == .loading {
                        self.usage.state = .unavailable("No Codex activity yet")
                    }
                }
            }
        }
    }

    private func refreshAccountLimits() {
        guard !limitsInFlight, Date() >= nextLimitsRefresh else { return }
        limitsInFlight = true
        nextLimitsRefresh = Date().addingTimeInterval(90)
        limitsQueue.async { [weak self] in
            let payload = CodexLimitsClient.read()
            DispatchQueue.main.async {
                guard let self else { return }
                self.limitsInFlight = false
                guard Preferences.shared.codexEnabled, let payload else { return }
                let now = Date()
                self.liveLimits = (now, payload)
                self.applyLimits(payload, at: now)
            }
        }
    }

    // MARK: Scanning (background queue)

    enum Event {
        case meta(file: URL, id: String, cwd: String, origin: String?)
        case started(id: String, at: Date)
        case completed(id: String, message: String?)
        case aborted(id: String)

        var isStatus: Bool {
            if case .meta = self { return false }
            return true
        }
    }

    private nonisolated(unsafe) var announced: Set<URL> = []
    private nonisolated(unsafe) var lastStatus: [URL: Event] = [:]

    nonisolated func scan() -> [Event] {
        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        if today != tokenDay {
            tokenDay = today
            tally = TokenTally()
        }
        let files = recentRollouts(modifiedSince: now.addingTimeInterval(-Constants.Agents.codexActiveWindow))
        var events: [Event] = []

        if !bootstrapped {
            bootstrapped = true
            bootstrapTokens(today: today)
            if let newest = recentRollouts(modifiedSince: now.addingTimeInterval(-14 * 86_400), limit: 1).first {
                readTailForLimits(newest)
            }
        }

        for file in files {
            guard !announced.contains(file) else {
                replay(file, into: &events, countTokens: true)
                continue
            }
            // First sight: announce the session with only its latest status, so history
            // replayed from the log never flashes old "done" banners.
            guard let meta = readSessionMeta(file) else { continue }
            announced.insert(file)
            sessionIDs[file] = meta.id
            events.append(.meta(file: file, id: meta.id, cwd: meta.cwd, origin: meta.origin))
            var history: [Event] = []
            if !reader.isTracking(file) {
                // A long tool result can push task_started out of any tail sample. Recover
                // the latest status once from the full log, then read only appended bytes.
                reader.seed(file, at: 0)
            }
            replay(file, into: &history, countTokens: true)
            if let latest = history.last(where: \.isStatus) ?? lastStatus[file] {
                events.append(latest)
            }
        }
        // Sessions whose log went quiet are no longer live.
        for file in announced.subtracting(files) {
            announced.remove(file)
            if let id = sessionIDs[file] { events.append(.aborted(id: id)) }
        }
        return events
    }

    private nonisolated func replay(_ file: URL, into events: inout [Event], countTokens: Bool) {
        let markers = ["\"task_started\"", "\"task_complete\"", "\"turn_aborted\"", "\"token_count\"", "\"session_meta\""].map(\.utf8Data)
        var newestStatus = lastStatus[file]
        reader.readNewLines(of: file, markers: markers) { line in
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
            let payload = json["payload"] as? [String: Any] ?? [:]
            let date = (json["timestamp"] as? String).flatMap(Self.parseDate) ?? Date()
            if (json["type"] as? String) == "session_meta" {
                let id = (payload["id"] as? String) ?? file.lastPathComponent
                sessionIDs[file] = id
                events.append(.meta(file: file, id: id, cwd: (payload["cwd"] as? String) ?? "", origin: payload["originator"] as? String))
                return
            }
            guard let id = sessionIDs[file] else { return }
            switch payload["type"] as? String {
            case "task_started":
                let event = Event.started(id: id, at: date)
                newestStatus = event
                events.append(event)
            case "task_complete":
                let event = Event.completed(id: id, message: payload["last_agent_message"] as? String)
                newestStatus = event
                events.append(event)
            case "turn_aborted":
                let event = Event.aborted(id: id)
                newestStatus = event
                events.append(event)
            case "token_count":
                if let limits = payload["rate_limits"] as? [String: Any], latestLimits.map({ $0.date <= date }) ?? true {
                    latestLimits = (date, limits)
                }
                if countTokens { count(payload, at: date) }
            default: break
            }
        }
        lastStatus[file] = newestStatus
    }

    private nonisolated func count(_ payload: [String: Any], at date: Date) {
        guard date >= tokenDay,
              let info = payload["info"] as? [String: Any],
              let last = info["last_token_usage"] as? [String: Any] else { return }
        let total = (last["total_tokens"] as? NSNumber)?.intValue ?? 0
        let output = (last["output_tokens"] as? NSNumber)?.intValue ?? 0
        tally.today += total
        tally.output += output
        tally.messages += 1
        let hour = Calendar.current.component(.hour, from: date)
        tally.hourly[hour] += total
    }

    /// Tallies today's tokens from every rollout touched today, then leaves the reader at file end.
    private nonisolated func bootstrapTokens(today: Date) {
        for file in recentRollouts(modifiedSince: today, limit: 200) {
            reader.seed(file, at: 0)
            var history: [Event] = []
            if let meta = readSessionMeta(file) { sessionIDs[file] = meta.id }
            replay(file, into: &history, countTokens: true)
            lastStatus[file] = history.last(where: \.isStatus)
        }
    }

    private nonisolated func readTailForLimits(_ file: URL) {
        guard !reader.isTracking(file) else { return }
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? UInt64) ?? 0
        let probe = JSONLTailReader()
        probe.seed(file, at: size > 524_288 ? size - 524_288 : 0)
        probe.readNewLines(of: file, markers: ["\"rate_limits\"".utf8Data]) { line in
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let payload = json["payload"] as? [String: Any],
                  let limits = payload["rate_limits"] as? [String: Any] else { return }
            let date = (json["timestamp"] as? String).flatMap(Self.parseDate) ?? Date.distantPast
            if latestLimits.map({ $0.date <= date }) ?? true { latestLimits = (date, limits) }
        }
    }

    private nonisolated func readSessionMeta(_ file: URL) -> (id: String, cwd: String, origin: String?)? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let head = handle.readData(ofLength: 64 * 1024)
        guard let newline = head.firstIndex(of: 0x0A),
              let json = try? JSONSerialization.jsonObject(with: head[..<newline]) as? [String: Any],
              (json["type"] as? String) == "session_meta",
              let payload = json["payload"] as? [String: Any] else { return nil }
        return ((payload["id"] as? String) ?? file.lastPathComponent, (payload["cwd"] as? String) ?? "", payload["originator"] as? String)
    }

    /// Rollout files modified since `date`, newest first. Walks only the day folders that can hold them.
    private nonisolated func recentRollouts(modifiedSince date: Date, limit: Int? = nil) -> [URL] {
        let fm = FileManager.default
        let root = sessionsRoot
        guard fm.fileExists(atPath: root.path) else { return [] }
        var candidates: [(URL, Date)] = []
        let calendar = Calendar.current
        // Sessions can keep writing into the folder of the day they started; look back a week.
        for dayOffset in 0..<8 {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            let folder = root
                .appendingPathComponent(String(format: "%04d", parts.year ?? 0))
                .appendingPathComponent(String(format: "%02d", parts.month ?? 0))
                .appendingPathComponent(String(format: "%02d", parts.day ?? 0))
            guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for file in files where file.lastPathComponent.hasPrefix("rollout-") && file.pathExtension == "jsonl" {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if modified >= date { candidates.append((file, modified)) }
            }
        }
        let sorted = candidates.sorted { $0.1 > $1.1 }.map(\.0)
        return limit.map { Array(sorted.prefix($0)) } ?? sorted
    }

    private nonisolated static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    // MARK: Applying (main)

    func apply(_ event: Event) {
        switch event {
        case .meta(_, let id, let cwd, let origin):
            store.upsert(id: id, provider: .codex) { session in
                session.cwd = cwd
                session.origin = origin
            }
        case .started(let id, let date):
            store.upsert(id: id, provider: .codex) { session in
                if session.status != .running { session.turnStartedAt = date }
                session.status = .running
            }
        case .completed(let id, let message):
            store.upsert(id: id, provider: .codex) { session in
                session.status = .done
                session.detail = message.flatMap { ClaudeHookHandler.summary($0, limit: 160) }
            }
        case .aborted(let id):
            store.upsert(id: id, provider: .codex) { $0.status = .idle }
        }
    }

    func applyLimits(_ payload: [String: Any], at date: Date, now: Date = Date()) {
        var windows: [UsageWindow] = []
        for key in ["primary", "secondary"] {
            guard let entry = payload[key] as? [String: Any],
                  let percent = (entry["used_percent"] as? NSNumber)?.doubleValue else { continue }
            let minutes = (entry["window_minutes"] as? NSNumber)?.doubleValue ?? 0
            let reset = (entry["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            let label: String
            switch minutes {
            case 300: label = "5 hours"
            case 10_080: label = "Week"
            case 1_440: label = "Day"
            default: label = minutes >= 1_440 ? "\(Int(minutes / 1_440)) days" : "\(Int(minutes / 60)) hours"
            }
            // A past reset cannot tell us how much was consumed in the new cycle.
            guard reset.map({ $0 > now }) ?? true else { continue }
            windows.append(UsageWindow(id: key, label: label, percent: percent, resetsAt: reset, duration: minutes * 60))
        }
        windows.sort { ($0.duration ?? 0) < ($1.duration ?? 0) }
        let plan = (payload["plan_type"] as? String).map { $0.capitalized }
        let stale = now.timeIntervalSince(date) > 180
        let state: ProviderUsage.State = windows.isEmpty
            ? .unavailable("Waiting for current Codex limits")
            : stale ? .unavailable("Last known limits · awaiting refresh") : .ready
        let next = ProviderUsage(provider: .codex, plan: plan, windows: windows, updatedAt: date, state: state)
        guard next != usage else { return }
        withAnimation(Motion.state) { usage = next }
        guard !stale else { return }
        for window in windows where window.severity != .normal {
            if warned.insert(window.warningKey(provider: "Codex")).inserted {
                onWarning?("Codex", window)
            }
        }
    }
}

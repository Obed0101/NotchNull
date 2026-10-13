import AppKit
import Combine
import SwiftUI

/// A widget file from ~/.notchnull/widgets, as written.
struct WidgetDefinition: Equatable {
    enum Size: String { case small, medium, wide }

    let id: String
    let file: URL
    let title: String
    let symbol: String?
    let tint: JSONValue?
    let size: Size
    /// Seconds between command runs; nil runs once.
    let refresh: TimeInterval?
    let command: String?
    let timeout: TimeInterval
    let view: JSONValue
    /// Optional wing: `{ "when": "{{data.failing}}", "leading": node, "trailing": node }`.
    let wing: JSONValue?
    /// Optional Home row: `{ "text": "{{data | count}} open", "progress": "{{data.ratio}}", "action": {…} }`.
    let home: JSONValue?
    let staticData: JSONValue
    let order: Int

    init(file: URL, json: JSONValue) throws {
        guard let object = json.object else { throw WidgetError.invalid("The file must be a JSON object.") }
        guard let view = object["view"], view.object != nil else { throw WidgetError.invalid("Missing \"view\": the layout to draw, like {\"type\": \"text\", \"text\": \"Hi\"}.") }
        self.file = file
        id = file.deletingPathExtension().lastPathComponent
        title = object["title"]?.string ?? id
        symbol = object["symbol"]?.string
        tint = object["tint"]
        size = object["size"]?.string.flatMap(Size.init(rawValue:)) ?? .medium
        refresh = object["refresh"]?.double.map { max(2, $0) }
        command = object["command"]?.string
        timeout = min(max(object["timeout"]?.double ?? 10, 1), 120)
        self.view = view
        wing = object["wing"]
        home = object["home"]
        staticData = object["data"] ?? .null
        order = Int(object["order"]?.double ?? 0)
        if object["enabled"]?.bool == false { throw WidgetError.disabled }
    }
}

enum WidgetError: Error, Equatable {
    case invalid(String)
    case disabled
}

/// A widget as the app currently sees it.
struct LoadedWidget: Identifiable, Equatable {
    enum State: Equatable {
        case loading
        case ready(JSONValue, Date)
        case failed(String)
    }

    let id: String
    let file: URL
    var definition: WidgetDefinition?
    var state: State

    var data: JSONValue {
        if case .ready(let data, _) = state { return data }
        return definition?.staticData ?? .null
    }

    var error: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    /// The widget's `home` block, when it asks for a row in the Home list.
    var homeRow: [String: JSONValue]? { definition?.home?.object }

    var scope: JSONValue { .object(["data": data]) }

    /// False while the row's own `when` is falsy.
    var showsHomeRow: Bool {
        guard let homeRow else { return false }
        return homeRow["when"].map { Template.resolve($0, in: scope)?.isTruthy ?? false } ?? true
    }
}

/// Loads every widget file, reloads on save, runs each widget's command on its schedule and
/// keeps the results. Commands run in your login shell with a timeout, like a shell prompt.
@MainActor
final class WidgetStore: ObservableObject {
    static let shared = WidgetStore()

    @Published private(set) var widgets: [LoadedWidget] = []

    private var watcher: FileWatcher?
    private var timers: [String: Timer] = [:]
    private var running: Set<String> = []
    private let queue = DispatchQueue(label: "dev.notchnull.widgets", attributes: .concurrent)

    func start() {
        reload()
        let watcher = FileWatcher(paths: [NotchHome.widgets]) { [weak self] paths in
            guard paths.contains(where: { $0.hasSuffix(".json") }) else { return }
            MainActor.assumeIsolated { self?.reload() }
        }
        watcher.start()
        self.watcher = watcher
    }

    /// Re-reads every file. Widgets whose file did not change keep their data.
    func reload(runCommands: Bool = true) {
        let files = ((try? FileManager.default.contentsOfDirectory(at: NotchHome.widgets, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
        var next: [LoadedWidget] = []
        for file in files {
            let id = file.deletingPathExtension().lastPathComponent
            let previous = widgets.first { $0.id == id }
            guard let data = try? Data(contentsOf: file) else { continue }
            guard let json = JSONValue.parse(data) else {
                next.append(LoadedWidget(id: id, file: file, definition: nil, state: .failed("\(file.lastPathComponent) is not valid JSON.")))
                continue
            }
            do {
                let definition = try WidgetDefinition(file: file, json: json)
                let unchanged = previous?.definition == definition
                next.append(LoadedWidget(id: id, file: file, definition: definition, state: unchanged ? previous!.state : (definition.command == nil ? .ready(definition.staticData, Date()) : .loading)))
            } catch WidgetError.disabled {
                continue
            } catch WidgetError.invalid(let message) {
                next.append(LoadedWidget(id: id, file: file, definition: nil, state: .failed(message)))
            } catch {
                continue
            }
        }
        next.sort { ($0.definition?.order ?? 0, $0.id) < ($1.definition?.order ?? 0, $1.id) }
        let changed = next.filter { widget in widgets.first { $0.id == widget.id }?.definition != widget.definition }
        withAnimation(Motion.state) { widgets = next }
        if runCommands {
            schedule()
            changed.forEach { run($0.id) }
        }
        updateWings()
        NotchStatus.write()
        Log.app.info("Widgets loaded: \(next.count)")
    }

    private func schedule() {
        timers.values.forEach { $0.invalidate() }
        timers = [:]
        for widget in widgets {
            guard let refresh = widget.definition?.refresh, widget.definition?.command != nil else { continue }
            let id = widget.id
            timers[id] = Timer.scheduledTimer(withTimeInterval: refresh, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.run(id) }
            }
        }
    }

    /// Runs a widget's command now.
    func run(_ id: String) {
        guard let definition = widgets.first(where: { $0.id == id })?.definition,
              let command = definition.command, !running.contains(id) else { return }
        running.insert(id)
        queue.async {
            let result = ShellCommand.run(command, timeout: definition.timeout, environment: ["NOTCHNULL_WIDGET": id])
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.finish(id, result) }
            }
        }
    }

    private func finish(_ id: String, _ result: ShellCommand.Result) {
        running.remove(id)
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        let state: LoadedWidget.State
        if result.timedOut {
            state = .failed("The command took longer than \(Int(widgets[index].definition?.timeout ?? 10))s and was stopped.")
        } else if result.status != 0 {
            let detail = result.stderr.isEmpty ? result.stdout : result.stderr
            state = .failed("Exit \(result.status): \(detail.suffix(300))")
        } else {
            state = .ready(Self.data(from: result.stdout), Date())
        }
        guard widgets[index].state != state else { return }
        withAnimation(Motion.value) { widgets[index].state = state }
        updateWings()
        NotchStatus.write()
    }

    /// Command output: JSON when it parses (object, array, number…), otherwise the text itself
    /// plus its lines, so `echo hi` works as well as `gh … --json`.
    nonisolated static func data(from output: String) -> JSONValue {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let json = JSONValue.parse(Data(trimmed.utf8)) { return json }
        return .object(["text": .string(trimmed), "lines": .array(trimmed.split(separator: "\n").map { .string(String($0)) })])
    }

    /// Data pushed from outside (`notchnull widget <id> --data '{…}'` or the API) replaces the
    /// command's result until the next run.
    func push(_ data: JSONValue, to id: String) -> Bool {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return false }
        withAnimation(Motion.value) { widgets[index].state = .ready(data, Date()) }
        updateWings()
        NotchStatus.write()
        return true
    }

    /// Performs a button's action: run a command, open a URL or file, copy text, or open a tab.
    func perform(_ action: JSONValue?, widget id: String, scope: JSONValue) {
        guard let action = action?.object else { return }
        if let command = action["run"].map({ Template.text($0, in: scope) }), !command.isEmpty {
            queue.async {
                _ = ShellCommand.run(command, timeout: 60, environment: ["NOTCHNULL_WIDGET": id])
                DispatchQueue.main.async { MainActor.assumeIsolated { self.run(id) } }
            }
        }
        if let target = action["open"].map({ Template.text($0, in: scope) }), !target.isEmpty {
            let url = target.contains("://") ? URL(string: target) : URL(fileURLWithPath: (target as NSString).expandingTildeInPath)
            if let url { NSWorkspace.shared.open(url) }
        }
        if let text = action["copy"].map({ Template.text($0, in: scope) }) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        if action["refresh"]?.bool == true { run(id) }
    }

    /// Widgets with a `wing` slide out of the notch while its `when` is true.
    private func updateWings() {
        for widget in widgets {
            guard let wing = widget.definition?.wing?.object else {
                CustomActivityStore.shared.remove(id: "widget:\(widget.id)")
                continue
            }
            let scope = JSONValue.object(["data": widget.data])
            let visible = wing["when"].map { Template.resolve($0, in: scope)?.isTruthy ?? false } ?? true
            if visible {
                CustomActivityStore.shared.set(CustomActivity(widget: widget, wing: wing, scope: scope))
            } else {
                CustomActivityStore.shared.remove(id: "widget:\(widget.id)")
            }
        }
    }

    /// Fixture entry point for snapshot rendering.
    func preview(_ widgets: [LoadedWidget]) {
        self.widgets = widgets
        updateWings()
    }

    /// Runs every command once and waits, for `--render`, so the image shows real data.
    func loadSynchronously() {
        reload(runCommands: false)
        for index in widgets.indices {
            guard let definition = widgets[index].definition, let command = definition.command else { continue }
            let result = ShellCommand.run(command, timeout: definition.timeout, environment: ["NOTCHNULL_WIDGET": widgets[index].id])
            if result.timedOut {
                widgets[index].state = .failed("The command took longer than \(Int(definition.timeout))s and was stopped.")
            } else if result.status != 0 {
                widgets[index].state = .failed("Exit \(result.status): \((result.stderr.isEmpty ? result.stdout : result.stderr).suffix(300))")
            } else {
                widgets[index].state = .ready(Self.data(from: result.stdout), Date())
            }
        }
        updateWings()
    }
}

/// Runs a shell command in the user's login shell with a timeout and bounded output.
enum ShellCommand {
    struct Result {
        var status: Int32
        var stdout: String
        var stderr: String
        var timedOut: Bool
    }

    static let outputLimit = 512 * 1024

    static func run(_ command: String, timeout: TimeInterval, environment: [String: String] = [:]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = FileManager.default.fileExists(atPath: NotchHome.root.path) ? NotchHome.root : Constants.Paths.home
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch {
            return Result(status: -1, stdout: "", stderr: error.localizedDescription, timedOut: false)
        }
        var timedOut = false
        let deadline = DispatchWorkItem {
            timedOut = true
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        // Read before waiting, so a chatty command cannot fill the pipe and stall.
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()
        func text(_ data: Data) -> String { String(decoding: data.prefix(outputLimit), as: UTF8.self) }
        return Result(status: process.terminationStatus, stdout: text(stdout), stderr: text(stderr).trimmingCharacters(in: .whitespacesAndNewlines), timedOut: timedOut)
    }
}

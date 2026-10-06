import AppKit
import Foundation

/// The local API on 127.0.0.1 (same port as the agent hooks, same token in ~/.notchnull/token).
/// Everything the CLI does goes through here, so any script or agent can drive the notch.
///
///     GET  /v1/status                   app, widgets and file errors
///     POST /v1/activity                 show a custom activity (see CustomActivity)
///     POST /v1/activity/hide            {"id": "…"}; without an id, hides all
///     POST /v1/open                     {"tab": "widgets"}; without a tab, opens the panel
///     POST /v1/close
///     POST /v1/widgets/reload
///     POST /v1/widgets/<id>/run         run the widget's command now
///     POST /v1/widgets/<id>/data        replace the widget's data with the body
///     GET  /v1/settings                 settings.json as the app sees it
///     POST /v1/settings                 apply part of settings.json, e.g. {"look": {"accent": "#FF5E8A"}}
///     GET  /v1/update                   this version, the newest release and where the update stands
///     POST /v1/update/check             ask GitHub now
///     POST /v1/update/install           download the waiting release, replace the app and relaunch
@MainActor
enum NotchAPI {
    /// Opens or closes the primary notch; set by the app delegate.
    static var openPanel: ((NotchTab?) -> Void)?
    static var closePanel: (() -> Void)?
    static var windowStatus: (() -> JSONValue)?

    static func handle(_ request: AgentEventServer.Request) -> AgentEventServer.Response {
        let path = request.path.split(separator: "?").first.map(String.init) ?? request.path
        let parts = Array(path.split(separator: "/").map(String.init).dropFirst()) // after "v1"
        let body = request.body.isEmpty ? JSONValue.object([:]) : JSONValue.parse(request.body)
        guard let body else { return .error("The body is not valid JSON.") }
        let route = "\(request.method) \(parts.joined(separator: "/"))"

        // /v1/widgets/<id>/run and /v1/widgets/<id>/data
        if request.method == "POST", parts.count == 3, parts[0] == "widgets" {
            let id = parts[1]
            guard WidgetStore.shared.widgets.contains(where: { $0.id == id }) else { return .error("No widget \(id).", status: 404) }
            switch parts[2] {
            case "run":
                WidgetStore.shared.run(id)
                return ok()
            case "data":
                _ = WidgetStore.shared.push(body, to: id)
                return ok()
            default:
                break
            }
        }

        switch route {
        case "GET status":
            return .json(NotchStatus.snapshot())
        case "POST activity":
            guard let activity = CustomActivity(payload: body) else {
                return .error("An activity needs at least one of: symbol, leading, trailing, title, subtitle.")
            }
            CustomActivityStore.shared.set(activity)
            return ok(["id": .string(activity.id)])
        case "POST activity/hide", "DELETE activity":
            if let id = body["id"]?.string { CustomActivityStore.shared.remove(id: id) } else { CustomActivityStore.shared.removeAll() }
            return ok()
        case "POST open":
            let tabName = body["tab"]?.string
            let tab = tabName.flatMap(NotchTab.init(rawValue:))
            if tabName != nil, tab == nil { return .error("Unknown tab. Tabs: \(NotchTab.allCases.map(\.rawValue).joined(separator: ", ")).") }
            openPanel?(tab)
            return ok()
        case "POST close":
            closePanel?()
            return ok()
        case "POST widgets/reload":
            WidgetStore.shared.reload()
            return ok(["widgets": .number(Double(WidgetStore.shared.widgets.count))])
        case "GET settings":
            return .json(SettingsFile.shared.snapshot())
        case "POST settings", "PATCH settings":
            guard let data = try? JSONSerialization.data(withJSONObject: body.any) else { return .error("Could not read the settings.") }
            let errors = SettingsFile.shared.apply(data, isPatch: true)
            return errors.isEmpty ? ok() : .json(.object(["ok": .bool(false), "errors": .array(errors.map { .string($0) })]), status: 400)
        case "GET update":
            return .json(UpdateService.shared.summary)
        case "POST update/check":
            Task { await UpdateService.shared.check() }
            return ok(["state": .string("checking")])
        case "POST update/install":
            guard case .available(let release) = UpdateService.shared.state else {
                return .error("No update is waiting. Check first: notchnull update")
            }
            Task { await UpdateService.shared.install() }
            return ok(["installing": .string(release.version.description)])
        default:
            return .error("Unknown endpoint \(request.method) \(path). See ~/.notchnull/skill/SKILL.md.", status: 404)
        }
    }

    private static func ok(_ extra: [String: JSONValue] = [:]) -> AgentEventServer.Response {
        .json(.object(["ok": .bool(true)].merging(extra) { $1 }))
    }
}

/// ~/.notchnull/status.json: what the app thinks of your files right now. Agents read this after
/// an edit instead of guessing whether it worked.
@MainActor
enum NotchStatus {
    private static var pending = false

    static func snapshot() -> JSONValue {
        let widgets: [JSONValue] = WidgetStore.shared.widgets.map { widget in
            var entry: [String: JSONValue] = [
                "id": .string(widget.id),
                "file": .string(widget.file.path),
                "title": .string(widget.definition?.title ?? widget.id),
            ]
            switch widget.state {
            case .loading: entry["state"] = .string("loading")
            case .ready(let data, let date):
                entry["state"] = .string("ready")
                entry["updatedAt"] = .string(ISO8601DateFormatter().string(from: date))
                entry["data"] = data
            case .failed(let message):
                entry["state"] = .string("error")
                entry["error"] = .string(message)
            }
            return .object(entry)
        }
        return .object([
            "app": .string(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"),
            "api": .string("http://127.0.0.1:\(Constants.Agents.eventServerPort)/v1"),
            "settingsErrors": .array(SettingsFile.shared.errors.map { .string($0) }),
            "widgets": .array(widgets),
            "activities": .array(CustomActivityStore.shared.items.keys.sorted().map { .string($0) }),
            "update": UpdateService.shared.summary,
            "windows": NotchAPI.windowStatus?() ?? .array([]),
            "displays": .array(NotchDisplay.connected.map { display in
                .object(["displayID": .number(Double(display.id)), "uuid": .string(display.persistentID),
                    "name": .string(display.name), "builtIn": .bool(display.builtIn),
                    "hasHardwareNotch": .bool(display.hasNotch), "scale": .number(display.scale),
                    "width": .number(display.frame.width), "height": .number(display.frame.height)])
            }),
        ])
    }

    /// Coalesced: many changes in one runloop turn write the file once.
    static func write() {
        // `notchnull render` runs in its own process; the running app owns this file.
        guard !pending, !Motion.isSnapshot else { return }
        pending = true
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                pending = false
                guard let data = try? JSONSerialization.data(withJSONObject: snapshot().any, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return }
                NotchHome.writeIfChanged(String(decoding: data, as: UTF8.self), to: NotchHome.status)
            }
        }
    }
}
